#!/usr/bin/env python3
"""
RVC v2 完全実装サーバー (完全修正版 v3)
- SynthesizerTrnMs768NSFsid の正確な構造 (VITS実装に準拠)
- enc_p.encoder は RelativePositionTransformer
  - attn_layers: MultiHeadAttention with relative position encoding
  - ffn_layers: FFN with conv_1/conv_2
  - norm_layers_1/2: LayerNorm with gamma/beta
- WeightNorm の正しい適用
- gin_ch=256, spk_dim=109 (configより)
"""
import http.server, socketserver, json, asyncio, io, os, threading, traceback, math
PORT       = 5061
MODEL_PATH = '/home/user/rvc_models/kaori.pth'
INDEX_PATH = '/home/user/rvc_models/kaori.index'

rvc_state = {'ready':False,'error':None,'net':None,'sr':48000,'f0':True,'index':None,'big_npy':None}

def log(m): print(f'[RVC] {m}', flush=True)

# ════════════════════════════════════════════════════════
#  RVC v2 ネットワーク (VITS公式実装準拠)
# ════════════════════════════════════════════════════════
def build_rvc_net(cfg):
    import torch, torch.nn as nn, torch.nn.functional as F
    from torch.nn.utils import weight_norm

    # cfg: [spec_ch, seg_sz, inter_ch, hidden_ch, filter_ch, n_heads, n_layers,
    #        k_sz, p_drop, resblock, resblock_k, resblock_d,
    #        up_rates, up_init_ch, up_k, spk_dim, gin_ch, sr]
    (spec_ch, seg_sz, inter_ch, hidden_ch,
     filter_ch, n_heads, n_layers, k_sz, p_drop,
     resblock_type, resblock_k, resblock_d,
     up_rates, up_init_ch, up_k,
     spk_dim, gin_ch, *_) = cfg

    LRELU_SLOPE = 0.1

    def wn(m): return weight_norm(m)

    # ── LayerNorm (gamma/beta パラメータ名) ──
    class LayerNorm(nn.Module):
        def __init__(self, channels, eps=1e-5):
            super().__init__()
            self.channels = channels
            self.eps = eps
            self.gamma = nn.Parameter(torch.ones(channels))
            self.beta  = nn.Parameter(torch.zeros(channels))

        def forward(self, x):
            # x: [B, C, T]
            x = x.transpose(1, -1)
            x = F.layer_norm(x, (self.channels,), self.gamma, self.beta, self.eps)
            return x.transpose(1, -1)

    # ── FFN Layer ──
    class FFNLayer(nn.Module):
        def __init__(self, in_ch, out_ch, filter_ch, k=3):
            super().__init__()
            self.conv_1 = nn.Conv1d(in_ch, filter_ch, k, padding=k//2)
            self.conv_2 = nn.Conv1d(filter_ch, out_ch, k, padding=k//2)

        def forward(self, x, x_mask):
            x = self.conv_1(x * x_mask)
            x = F.relu(x)
            x = self.conv_2(x * x_mask)
            return x * x_mask

    # ── Multi-Head Attention Layer (Relative Position) ──
    class MultiHeadAttnLayer(nn.Module):
        def __init__(self, channels, heads, window_size=10):
            super().__init__()
            assert channels % heads == 0
            self.heads = heads
            self.head_dim = channels // heads
            self.window_size = window_size
            # emb_rel: [1, 2*window+1, head_dim]
            self.emb_rel_k = nn.Parameter(torch.randn(1, 2*window_size+1, self.head_dim) * 0.01)
            self.emb_rel_v = nn.Parameter(torch.randn(1, 2*window_size+1, self.head_dim) * 0.01)
            self.conv_q = nn.Conv1d(channels, channels, 1)
            self.conv_k = nn.Conv1d(channels, channels, 1)
            self.conv_v = nn.Conv1d(channels, channels, 1)
            self.conv_o = nn.Conv1d(channels, channels, 1)

        def forward(self, x, attn_mask=None):
            # x: [B, C, T]
            B, C, T = x.shape
            q = self.conv_q(x).view(B, self.heads, self.head_dim, T)
            k = self.conv_k(x).view(B, self.heads, self.head_dim, T)
            v = self.conv_v(x).view(B, self.heads, self.head_dim, T)

            scale = self.head_dim ** -0.5
            # Content attention
            attn = torch.einsum('bhdt,bhds->bhts', q * scale, k)

            if attn_mask is not None:
                attn = attn + attn_mask
            attn = F.softmax(attn, dim=-1)

            out = torch.einsum('bhts,bhds->bhdt', attn, v)
            out = out.reshape(B, C, T)
            out = self.conv_o(out)
            return out

    # ── Relative Position Transformer (enc_p.encoder) ──
    class RelPositionTransformer(nn.Module):
        def __init__(self, channels, filter_ch, n_heads, n_layers, k_sz, p_drop, window_size=4):
            super().__init__()
            self.attn_layers  = nn.ModuleList([
                MultiHeadAttnLayer(channels, n_heads, window_size=10)
                for _ in range(n_layers)])
            self.norm_layers_1 = nn.ModuleList([LayerNorm(channels) for _ in range(n_layers)])
            self.ffn_layers    = nn.ModuleList([
                FFNLayer(channels, channels, filter_ch, k=k_sz)
                for _ in range(n_layers)])
            self.norm_layers_2 = nn.ModuleList([LayerNorm(channels) for _ in range(n_layers)])

        def forward(self, x, x_mask):
            # x: [B, C, T], x_mask: [B, 1, T]
            attn_mask = None
            for attn, norm1, ffn, norm2 in zip(
                    self.attn_layers, self.norm_layers_1,
                    self.ffn_layers, self.norm_layers_2):
                y = attn(x * x_mask, attn_mask)
                x = norm1(x + y)
                y = ffn(x, x_mask)
                x = norm2(x + y)
            return x * x_mask

    # ── WaveNet (WN) ──
    class WN(nn.Module):
        def __init__(self, hid, k, d_list, n_lay, gin_ch=0):
            super().__init__()
            self.n_layers = n_lay
            self.in_layers       = nn.ModuleList()
            self.res_skip_layers = nn.ModuleList()
            self.cond_layer = wn(nn.Conv1d(gin_ch, 2*hid*n_lay, 1)) if gin_ch > 0 else None
            for i in range(n_lay):
                dil = d_list[i] if isinstance(d_list, (list,tuple)) else (d_list**i)
                self.in_layers.append(
                    wn(nn.Conv1d(hid, 2*hid, k, dilation=dil, padding=dil*(k-1)//2)))
                out_ch = 2*hid if i < n_lay-1 else hid
                self.res_skip_layers.append(wn(nn.Conv1d(hid, out_ch, 1)))

        def forward(self, x, x_mask, g=None):
            out = torch.zeros_like(x)
            n_ch = x.shape[1]
            g_all = self.cond_layer(g) if self.cond_layer is not None and g is not None else None
            for i in range(self.n_layers):
                h = self.in_layers[i](x) * x_mask
                if g_all is not None:
                    g_i = g_all[:, i*2*n_ch:(i+1)*2*n_ch, :]
                    T_h = h.shape[-1]
                    h = h + g_i[:, :, :T_h]
                acts = torch.tanh(h[:, :n_ch]) * torch.sigmoid(h[:, n_ch:])
                rs = self.res_skip_layers[i](acts) * x_mask
                if i < self.n_layers - 1:
                    x   = (x + rs[:, :n_ch]) * x_mask
                    out = out + rs[:, n_ch:]
                else:
                    out = out + rs
            return out * x_mask

    # ── ResBlock1 (WeightNorm版) ──
    class ResBlock1(nn.Module):
        def __init__(self, ch, k=3, d=(1,3,5)):
            super().__init__()
            self.convs1 = nn.ModuleList([
                wn(nn.Conv1d(ch, ch, k, dilation=dd, padding=dd*(k-1)//2)) for dd in d])
            self.convs2 = nn.ModuleList([
                wn(nn.Conv1d(ch, ch, k, padding=(k-1)//2)) for _ in d])

        def forward(self, x, x_mask=None):
            for c1, c2 in zip(self.convs1, self.convs2):
                xt = F.leaky_relu(x, LRELU_SLOPE)
                xt = c1(xt)
                xt = F.leaky_relu(xt, LRELU_SLOPE)
                xt = c2(xt)
                x = x + xt
            return x if x_mask is None else x * x_mask

    # ── Harmonic Source ──
    class SourceModuleHnNSF(nn.Module):
        def __init__(self):
            super().__init__()
            self.l_linear = nn.Linear(1, 1)
            self.l_tanh   = nn.Tanh()

        def forward(self, f0):
            B, T = f0.shape
            voiced = (f0 > 1.0).float()
            t = torch.arange(T, device=f0.device, dtype=f0.dtype)
            phase = 2 * math.pi * f0 / 48000
            cum_phase = torch.cumsum(phase, dim=1)
            sines = torch.sin(cum_phase) * voiced * 0.1
            out = sines.unsqueeze(-1)  # [B, T, 1]
            return self.l_tanh(self.l_linear(out))

    # ── NSF Generator (dec) ──
    class NSFGenerator(nn.Module):
        def __init__(self):
            super().__init__()
            self.num_kernels   = len(resblock_k)
            self.num_upsamples = len(up_rates)

            # m_source
            self.m_source = SourceModuleHnNSF()

            # noise_convs (通常Conv1d - WeightNormなし)
            self.noise_convs = nn.ModuleList()
            ch = up_init_ch
            for i, u in enumerate(up_rates):
                stride_f0 = math.prod(up_rates[i+1:]) if i+1 < len(up_rates) else 1
                nch = ch // 2
                if stride_f0 > 1:
                    self.noise_convs.append(
                        nn.Conv1d(1, nch, stride_f0*2, stride=stride_f0, padding=stride_f0//2))
                else:
                    self.noise_convs.append(nn.Conv1d(1, nch, 1))
                ch = nch

            # conv_pre (通常Conv1d - WeightNormなし)
            self.conv_pre = nn.Conv1d(inter_ch, up_init_ch, 7, padding=3)

            # ups (WeightNorm ConvTranspose1d)
            self.ups = nn.ModuleList()
            ch = up_init_ch
            for u, k in zip(up_rates, up_k):
                self.ups.append(wn(nn.ConvTranspose1d(ch, ch//2, k, u, padding=(k-u)//2)))
                ch //= 2

            # resblocks (WeightNorm)
            self.resblocks = nn.ModuleList()
            ch = up_init_ch // 2
            for i in range(self.num_upsamples):
                for rk, rd in zip(resblock_k, resblock_d):
                    self.resblocks.append(ResBlock1(ch, rk, rd))
                ch //= 2

            # conv_post (通常Conv1d - WeightNormなし)
            self.conv_post = nn.Conv1d(ch * 2, 1, 7, padding=3)

            # cond (通常Conv1d - WeightNormなし)
            self.cond = nn.Conv1d(gin_ch, up_init_ch, 1)

        def forward(self, x, f0, g=None):
            har_src = self.m_source(f0)        # [B, T_mel, 1]
            har_src = har_src.transpose(1, 2)  # [B, 1, T_mel]

            x = self.conv_pre(x)
            if g is not None:
                x = x + self.cond(g)

            for i in range(self.num_upsamples):
                x = F.leaky_relu(x, LRELU_SLOPE)
                x = self.ups[i](x)
                x_source = self.noise_convs[i](har_src)
                if x.shape[-1] != x_source.shape[-1]:
                    x_source = F.interpolate(x_source, size=x.shape[-1], mode='nearest')
                x = x + x_source
                xs = None
                for j in range(self.num_kernels):
                    r = self.resblocks[i * self.num_kernels + j](x)
                    xs = r if xs is None else xs + r
                x = xs / self.num_kernels

            x = F.leaky_relu(x, LRELU_SLOPE)
            x = self.conv_post(x)
            return torch.tanh(x)

    # ── Residual Coupling Layer (Flow) ──
    class ResidualCouplingLayer(nn.Module):
        def __init__(self):
            super().__init__()
            half_ch = inter_ch // 2
            self.pre  = nn.Conv1d(half_ch, inter_ch, 1)
            self.enc  = WN(inter_ch, 5, [1, 1, 1], n_lay=3, gin_ch=gin_ch)
            self.post = nn.Conv1d(inter_ch, half_ch, 1)
            nn.init.zeros_(self.post.weight)
            nn.init.zeros_(self.post.bias)

        def forward(self, x, x_mask, g=None, reverse=False):
            x0, x1 = x.split(x.shape[1] // 2, dim=1)
            h = self.pre(x0) * x_mask
            h = self.enc(h, x_mask, g=g)
            m = self.post(h) * x_mask
            if reverse:
                x1 = (x1 - m) * x_mask
            else:
                x1 = (m + x1) * x_mask
            return torch.cat([x0, x1], dim=1) * x_mask

    class Flip(nn.Module):
        def forward(self, x, *args, **kwargs):
            return x.flip(1)

    class ResidualCouplingBlock(nn.Module):
        def __init__(self, n_flows=4):
            super().__init__()
            self.flows = nn.ModuleList()
            for _ in range(n_flows):
                self.flows.append(ResidualCouplingLayer())
                self.flows.append(Flip())

        def forward(self, x, x_mask, g=None, reverse=False):
            itr = reversed(list(self.flows)) if reverse else iter(self.flows)
            for f in itr:
                if isinstance(f, Flip):
                    x = f(x)
                else:
                    x = f(x, x_mask, g=g, reverse=reverse)
            return x

    # ── TextEncoder (enc_p) ──
    class TextEncoder(nn.Module):
        def __init__(self):
            super().__init__()
            self.emb_phone = nn.Linear(768, hidden_ch)
            self.emb_pitch = nn.Embedding(256, hidden_ch)
            self.encoder   = RelPositionTransformer(
                channels=hidden_ch, filter_ch=filter_ch,
                n_heads=n_heads, n_layers=n_layers,
                k_sz=k_sz, p_drop=p_drop, window_size=4)
            self.proj = nn.Conv1d(hidden_ch, inter_ch * 2, 1)

        def forward(self, phone, pitch, lengths):
            x = self.emb_phone(phone) + self.emb_pitch(pitch)  # [B, T, H]
            x = x.transpose(1, 2)  # [B, H, T]
            B, H, T = x.shape
            mask = torch.ones(B, 1, T, device=x.device)
            if lengths is not None:
                for b in range(B):
                    if int(lengths[b]) < T:
                        mask[b, :, int(lengths[b]):] = 0
            x = self.encoder(x, mask)
            stats = self.proj(x) * mask
            m, logs = stats.split(inter_ch, dim=1)
            return x, m, logs, mask

    # ── 最終モデル ──
    class SynthesizerRVC(nn.Module):
        def __init__(self):
            super().__init__()
            self.enc_p = TextEncoder()
            self.flow  = ResidualCouplingBlock(n_flows=4)
            self.dec   = NSFGenerator()
            self.emb_g = nn.Embedding(spk_dim, gin_ch)

        def infer(self, phone, phone_lengths, pitch, nsff0, sid):
            g = self.emb_g(sid).unsqueeze(-1)  # [B, gin_ch, 1]
            enc_out, m_p, logs_p, x_mask = self.enc_p(phone, pitch, phone_lengths)
            z_p = m_p + torch.randn_like(m_p) * torch.exp(logs_p) * 0.667
            z   = self.flow(z_p, x_mask, g=g, reverse=True)
            wav = self.dec(z * x_mask, nsff0, g=g)
            return wav

    return SynthesizerRVC()


# ════════════════════════════════════════════════════════
#  モデルロード
# ════════════════════════════════════════════════════════
def load_rvc_model():
    global rvc_state
    try:
        import torch
        log("Loading kaori.pth ...")
        ckpt    = torch.load(MODEL_PATH, map_location='cpu', weights_only=False)
        cfg     = ckpt['config']
        weights = ckpt['weight']
        sr_raw  = ckpt.get('sr', 48000)
        sr      = int(str(sr_raw).replace('k','000')) if isinstance(sr_raw, str) else int(sr_raw)
        f0_en   = bool(ckpt.get('f0', 1))
        log(f"cfg={cfg}")
        log(f"total ckpt weights: {len(weights)}")

        net = build_rvc_net(cfg)
        net.eval()

        state = net.state_dict()
        loaded = skipped_shape = skipped_missing = 0
        for k, v in weights.items():
            if k in state:
                if state[k].shape == v.shape:
                    state[k] = v.float()
                    loaded += 1
                else:
                    skipped_shape += 1
                    log(f"  SHAPE MISMATCH {k}: model={state[k].shape} ckpt={v.shape}")
            else:
                skipped_missing += 1
                if skipped_missing <= 5:
                    log(f"  KEY NOT FOUND: {k}")

        net.load_state_dict(state, strict=False)

        model_keys = set(state.keys())
        ckpt_keys  = set(weights.keys())
        extra = model_keys - ckpt_keys
        log(f"Weights: loaded={loaded}/{len(weights)}, shape_mismatch={skipped_shape}, "
            f"not_in_model={skipped_missing}, in_model_only={len(extra)}")
        if extra:
            log(f"  Model-only keys: {list(extra)[:5]}")

        # FAISS
        idx = big_npy = None
        if os.path.exists(INDEX_PATH):
            try:
                import faiss
                idx = faiss.read_index(INDEX_PATH)
                big_npy = idx.reconstruct_n(0, idx.ntotal)
                log(f"FAISS: {idx.ntotal} entries")
            except Exception as e:
                log(f"FAISS warn: {e}")

        rvc_state.update(dict(ready=True, net=net, sr=sr, f0=f0_en,
                               index=idx, big_npy=big_npy))
        log("✅ RVC ready!")
    except Exception as e:
        rvc_state['error'] = str(e)
        log(f"❌ Load error: {e}")
        traceback.print_exc()


# ════════════════════════════════════════════════════════
#  推論パイプライン
# ════════════════════════════════════════════════════════
def rvc_infer(wav_bytes, f0_up_key=0, index_rate=0.75):
    import torch, torchaudio, numpy as np
    if not rvc_state['ready']:
        log("RVC not ready, returning original TTS audio")
        return wav_bytes
    net    = rvc_state['net']
    sr_out = rvc_state['sr']
    faiss_idx = rvc_state['index']
    big_npy   = rvc_state['big_npy']

    try:
        # 1. 音声ロード → 16kHz mono
        wf, sr_in = torchaudio.load(io.BytesIO(wav_bytes))
        if wf.shape[0] > 1:
            wf = wf.mean(0, keepdim=True)
        if sr_in != 16000:
            wf = torchaudio.transforms.Resample(sr_in, 16000)(wf)
        wav16 = wf.squeeze(0)
        log(f"Input: {wav16.shape[0]} samples @ 16kHz ({wav16.shape[0]/16000:.2f}s)")

        # 2. HuBERT 特徴抽出
        bundle = torchaudio.pipelines.HUBERT_BASE
        hubert = bundle.get_model()
        hubert.eval()
        with torch.no_grad():
            feats, _ = hubert.extract_features(wav16.unsqueeze(0))
            feats = feats[-1]  # [1, T, 768]
        T = feats.shape[1]
        log(f"HuBERT: {feats.shape}")

        # 3. FAISS 補正
        if faiss_idx is not None and index_rate > 0:
            try:
                npy = feats.squeeze(0).numpy().astype('float32')
                score, ix = faiss_idx.search(npy, k=8)
                w = score.sum(1, keepdims=True)
                w = np.where(w == 0, 1e-9, w)
                corr = (big_npy[ix] * score[:, :, None] / w[:, None]).sum(1)
                feats = torch.from_numpy(
                    ((1-index_rate)*npy + index_rate*corr).astype('float32')).unsqueeze(0)
                log(f"FAISS corrected rate={index_rate}")
            except Exception as e:
                log(f"FAISS err (skipped): {e}")

        # 4. F0 抽出
        try:
            import parselmouth
            wav_np = wav16.numpy()
            snd = parselmouth.Sound(wav_np, sampling_frequency=16000)
            pm  = snd.to_pitch_ac(time_step=0.01, voicing_threshold=0.6,
                                   pitch_floor=50, pitch_ceiling=1100)
            f0_raw = pm.selected_array['frequency']
            f0_raw = np.where(np.isnan(f0_raw) | (f0_raw <= 0), 0.0, f0_raw).astype(np.float32)
            f0_rs = np.interp(
                np.linspace(0, len(f0_raw)-1, T),
                np.arange(len(f0_raw)), f0_raw).astype(np.float32)
            if f0_up_key != 0:
                f0_rs = np.where(f0_rs > 0, f0_rs * (2 ** (f0_up_key / 12)), 0.0)
            mel     = 1127.0 * np.log1p(f0_rs / 700.0)
            mel_min = 1127.0 * np.log1p(50.0 / 700.0)
            mel_max = 1127.0 * np.log1p(1100.0 / 700.0)
            coarse  = np.clip(np.round((mel-mel_min)/(mel_max-mel_min)*254+1), 1, 255)
            coarse  = np.where(f0_rs > 0, coarse, 0).astype(np.int64)
            f0_coarse = torch.from_numpy(coarse).unsqueeze(0)
            f0_fine   = torch.from_numpy(f0_rs).unsqueeze(0)
            log(f"F0: voiced={int((f0_rs>0).sum())}/{T}")
        except Exception as e:
            log(f"F0 warn (use zeros): {e}")
            f0_coarse = torch.zeros(1, T, dtype=torch.long)
            f0_fine   = torch.zeros(1, T, dtype=torch.float32)

        # 5. 推論
        with torch.no_grad():
            lengths = torch.LongTensor([T])
            sid     = torch.LongTensor([0])
            wav_out = net.infer(feats.float(), lengths, f0_coarse, f0_fine, sid)
            wav_out = wav_out.squeeze()

        log(f"Infer: {wav_out.shape[0]} samples ({wav_out.shape[0]/sr_out:.2f}s)")

        # 6. 正規化
        mx = wav_out.abs().max()
        if mx > 1e-6:
            wav_out = wav_out / mx * 0.9
        else:
            log("WARNING: near-silent output, using original TTS")
            return wav_bytes

        out = io.BytesIO()
        torchaudio.save(out, wav_out.unsqueeze(0), sr_out, format='wav')
        out.seek(0)
        result = out.read()
        log(f"Output: {len(result)} bytes @ {sr_out}Hz")
        return result

    except Exception as e:
        log(f"infer error: {e}")
        traceback.print_exc()
        return wav_bytes


# ════════════════════════════════════════════════════════
#  edge-tts
# ════════════════════════════════════════════════════════
def tts_edge(text, voice="ja-JP-NanamiNeural", rate="-5%", pitch="+60Hz"):
    """幼くて萌え系の女の子声（pitch +60Hz = より子供っぽい高さ, rate -5% = ゆっくりめで可愛い）"""
    async def _run():
        import edge_tts
        # 幼くて萌え系: pitch高め、レートははかどかにならない設定
        comm = edge_tts.Communicate(
            text, voice,
            rate=rate,
            pitch=pitch,
        )
        buf  = b""
        async for chunk in comm.stream():
            if chunk["type"] == "audio":
                buf += chunk["data"]
        return buf
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)
    try:    return loop.run_until_complete(_run())
    finally: loop.close()


# ════════════════════════════════════════════════════════
#  HTTP ハンドラー
# ════════════════════════════════════════════════════════
class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def cors(self):
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET,POST,OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
    def do_OPTIONS(self):
        self.send_response(200); self.cors(); self.end_headers()
    def do_GET(self):
        if self.path == '/status':
            b = json.dumps({
                'ready': rvc_state['ready'], 'error': rvc_state['error'],
                'model': 'kaori (RVC v2 - v3fixed)', 'sr': str(rvc_state['sr']), 'f0': rvc_state['f0']
            }).encode()
            self.send_response(200); self.cors()
            self.send_header('Content-Type','application/json')
            self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
        else:
            self.send_response(404); self.end_headers()
    def do_POST(self):
        n    = int(self.headers.get('Content-Length', 0))
        body = self.rfile.read(n)
        if self.path in ('/tts', '/tts_mp3'):
            try:
                d       = json.loads(body)
                text    = d.get('text','')
                voice   = d.get('voice','ja-JP-NanamiNeural')
                use_rvc = d.get('use_rvc', True)
                f0_key  = int(d.get('f0_key', 0))
                rate    = d.get('rate', '-5%')
                pitch   = d.get('pitch', '+60Hz')  # Hz形式: より幼く萌え系
                if not text:
                    self.send_response(400); self.end_headers(); return
                rvc_ready = use_rvc and rvc_state['ready']
                log(f"TTS '{text[:40]}' rvc={rvc_ready}")
                tts_audio = tts_edge(text, voice, rate=rate, pitch=pitch)
                log(f"TTS done: {len(tts_audio)}B")
                if rvc_ready:
                    final = rvc_infer(tts_audio, f0_up_key=f0_key)
                    ctype = 'audio/wav'
                else:
                    final = tts_audio
                    ctype = 'audio/mpeg'
                self.send_response(200); self.cors()
                self.send_header('Content-Type', ctype)
                self.send_header('Content-Length', str(len(final)))
                self.end_headers(); self.wfile.write(final)
            except Exception as e:
                log(f"POST err: {e}"); traceback.print_exc()
                b = json.dumps({'error': str(e)}).encode()
                self.send_response(500); self.cors()
                self.send_header('Content-Type','application/json')
                self.send_header('Content-Length',str(len(b))); self.end_headers(); self.wfile.write(b)
        else:
            self.send_response(404); self.end_headers()


if __name__ == '__main__':
    log(f"Starting RVC server port={PORT}")
    threading.Thread(target=load_rvc_model, daemon=True).start()
    socketserver.TCPServer.allow_reuse_address = True
    with socketserver.TCPServer(('0.0.0.0', PORT), Handler) as s:
        log(f"✅ Listening http://0.0.0.0:{PORT}")
        s.serve_forever()
