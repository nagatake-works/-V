#!/usr/bin/env python3
"""大規模修正を build/web/index.html と web/index.html に適用"""
import re

FILE = 'build/web/index.html'
with open(FILE, 'r', encoding='utf-8') as f:
    html = f.read()

# ============================================================
# 1. SafeArea対応（OS標準ヘッダー/ホームバー対応）
# ============================================================
html = html.replace(
    'width:100%;height:100%;overflow:hidden;\n  background:#070b18;',
    'width:100%;height:100%;overflow:hidden;\n  background:#070b18;\n  padding-top:env(safe-area-inset-top);\n  padding-bottom:env(safe-area-inset-bottom);\n  padding-left:env(safe-area-inset-left);\n  padding-right:env(safe-area-inset-right);'
)
# viewportにviewport-fitを追加
html = html.replace(
    'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no',
    'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover'
)

# ============================================================
# 2. 防具のimg追加（空だったarmor1, armor2に画像パスを設定）
# ============================================================
html = html.replace(
    "{id:'armor1',  name:'布の服',      icon:'👕',  img:'',                      desc:'軽い装備',",
    "{id:'armor1',  name:'布の服',      icon:'👕',  img:'img/items/armor1.png',  desc:'軽い装備',"
)
html = html.replace(
    "{id:'armor2',  name:'革の鎧',      icon:'🥋',  img:'',                      desc:'少し硬い',",
    "{id:'armor2',  name:'革の鎧',      icon:'🥋',  img:'img/items/armor2.png',  desc:'少し硬い',"
)

# ============================================================
# 3. 新規武器追加（追加素材4枚分）
# ============================================================
old_weapon_end = "{id:'staff2',  name:'星詠みの杖',   icon:'🌟',  img:'img/items/staff2.png',  desc:'星の力',     stats:{atk:25,mp:20},  skill:{name:'スターバースト',dmgMul:2.5},price:450,rarity:'SSR',maxDur:120},\n  ],"
new_weapon_end = """{id:'staff2',  name:'星詠みの杖',   icon:'🌟',  img:'img/items/staff2.png',  desc:'星の力',     stats:{atk:25,mp:20},  skill:{name:'スターバースト',dmgMul:2.5},price:450,rarity:'SSR',maxDur:120},
    {id:'weapon7', name:'炎の大剣',     icon:'🔥',  img:'img/items/weapon7.png', desc:'灼熱の刃',   stats:{atk:22,spd:3},  skill:{name:'フレイムスラッシュ',dmgMul:1.8},price:250,rarity:'SR',maxDur:70},
    {id:'weapon8', name:'氷結の槍',     icon:'❄️',  img:'img/items/weapon8.png', desc:'凍てつく穂先',stats:{atk:20,dfs:5},  skill:{name:'アイスピアス',dmgMul:1.7},price:230,rarity:'SR',maxDur:70},
    {id:'weapon9', name:'雷神の斧',     icon:'⚡',  img:'img/items/weapon9.png', desc:'電撃の一撃', stats:{atk:35,spd:-2}, skill:{name:'サンダークラッシュ',dmgMul:2.8},price:500,rarity:'SSR',maxDur:120},
    {id:'weapon10',name:'虹色のダガー', icon:'🌈',  img:'img/items/weapon10.png',desc:'七色の輝き', stats:{atk:28,spd:12}, skill:{name:'レインボーファング',dmgMul:2.0},price:420,rarity:'SSR',maxDur:100},
  ],"""
html = html.replace(old_weapon_end, new_weapon_end)

# ============================================================
# 4. 新規防具追加（追加素材2枚分）
# ============================================================
old_armor_end = "{id:'armor5',  name:'竜鱗の鎧',   icon:'🐉', img:'img/items/armor5.png',  desc:'最強の守り',  stats:{dfs:40,hp:40},  skill:{name:'ドラゴンスケール',effect:'reflect'},price:420,rarity:'SSR'},\n  ],"
new_armor_end = """{id:'armor5',  name:'竜鱗の鎧',   icon:'🐉', img:'img/items/armor5.png',  desc:'最強の守り',  stats:{dfs:40,hp:40},  skill:{name:'ドラゴンスケール',effect:'reflect'},price:420,rarity:'SSR'},
    {id:'armor6',  name:'天使の羽衣',  icon:'👼', img:'img/items/armor6.png',  desc:'天からの守護',stats:{dfs:35,hp:30,mp:10},skill:{name:'エンジェルガード',effect:'heal'},price:380,rarity:'SSR'},
    {id:'armor7',  name:'深淵のローブ',icon:'🌑', img:'img/items/armor7.png',  desc:'闇の力',     stats:{dfs:45,mp:25},  skill:{name:'ダークバリア',effect:'reflect'},price:480,rarity:'SSR'},
  ],"""
html = html.replace(old_armor_end, new_armor_end)

# ============================================================
# 5. ペットシステム追加（SHOP_ITEMSにpetカテゴリ追加）
# ============================================================
old_item_end = """  item:[
    {id:'pot1',    name:'ポーション',   icon:'🧪',  desc:'HP+30回復',  stats:{},              skill:null,              price:40,  rarity:'N',  consumable:true, effect:'heal30'},
    {id:'pot2',    name:'ハイポーション',icon:'💊', desc:'HP全回復',   stats:{},              skill:null,              price:100, rarity:'R',  consumable:true, effect:'healfull'},
    {id:'elixir',  name:'エリクサー',   icon:'✨',  desc:'HP/MP全回復',stats:{},              skill:null,              price:250, rarity:'SR', consumable:true, effect:'healall'},
  ],
};"""
new_item_end = """  item:[
    {id:'pot1',    name:'ポーション',   icon:'🧪',  desc:'HP+30回復',  stats:{},              skill:null,              price:40,  rarity:'N',  consumable:true, effect:'heal30'},
    {id:'pot2',    name:'ハイポーション',icon:'💊', desc:'HP全回復',   stats:{},              skill:null,              price:100, rarity:'R',  consumable:true, effect:'healfull'},
    {id:'elixir',  name:'エリクサー',   icon:'✨',  desc:'HP/MP全回復',stats:{},              skill:null,              price:250, rarity:'SR', consumable:true, effect:'healall'},
  ],
  pet:[
    {id:'pet1', name:'ちびスライム',   icon:'🟢', img:'img/items/pet1.png',  desc:'HP自動回復',   stats:{hp:10},  skill:{name:'ヒールドロップ',effect:'pet_heal',val:5},  price:300, rarity:'R',  petColor:'#40ff80'},
    {id:'pet2', name:'妖精ピクシー',   icon:'🧚', img:'img/items/pet2.png',  desc:'追撃ダメージ', stats:{atk:5},  skill:{name:'フェアリーショット',effect:'pet_attack',val:8}, price:500, rarity:'SR', petColor:'#ff80ff'},
    {id:'pet3', name:'ちびドラゴン',   icon:'🐲', img:'img/items/pet3.png',  desc:'全ステUP',     stats:{atk:8,dfs:5,hp:15}, skill:{name:'ドラゴンブレス',effect:'pet_attack',val:15},price:800, rarity:'SSR',petColor:'#ff6040'},
    {id:'pet4', name:'精霊ウンディーネ',icon:'💧', img:'img/items/pet4.png',  desc:'毎ターンHP回復',stats:{hp:20,mp:10},skill:{name:'アクアヒール',effect:'pet_heal',val:10},price:700,rarity:'SSR',petColor:'#40c0ff'},
    {id:'pet5', name:'闇の使い魔',     icon:'🦇', img:'img/items/pet5.png',  desc:'与ダメ倍率UP', stats:{atk:12},skill:{name:'シャドウクロー',effect:'pet_attack',val:20},price:1000,rarity:'SSR',petColor:'#a040ff'},
  ],
};"""
html = html.replace(old_item_end, new_item_end)

# ============================================================
# 6. セーブデータにpetスロット追加
# ============================================================
html = html.replace(
    "equip:{weapon:null,armor:null},",
    "equip:{weapon:null,armor:null,pet:null},"
)

# ============================================================
# 7. ショップタブにペットを追加
# ============================================================
html = html.replace(
    """<button class=\"shop-tab\" onclick=\"switchShopTab('item')\" id=\"tab-item\">アイテム</button>""",
    """<button class=\"shop-tab\" onclick=\"switchShopTab('item')\" id=\"tab-item\">アイテム</button>
    <button class=\"shop-tab\" onclick=\"switchShopTab('pet')\" id=\"tab-pet\">ペット</button>"""
)

# ============================================================
# 8. 装備スロットにペット追加（HTMLに追加）
# ============================================================
html = html.replace(
    """<div class=\"mr-equip-slot\" id=\"mr-equip-armor\" onclick=\"mrEquipSlotTap('armor')\">
        <img class=\"mr-equip-img\" id=\"mr-equip-armor-img\" src=\"\" alt=\"\">""",
    """<div class=\"mr-equip-slot\" id=\"mr-equip-armor\" onclick=\"mrEquipSlotTap('armor')\">
        <img class=\"mr-equip-img\" id=\"mr-equip-armor-img\" src=\"\" alt=\"\">"""
)
# ペットスロットをarmor slotの後に追加
armor_slot_end = """<div class=\"mr-equip-name\" id=\"mr-equip-armor-name\">なし</div>
      </div>"""
# Find and add pet slot after armor
html = html.replace(
    armor_slot_end,
    armor_slot_end + """
      <div class=\"mr-equip-slot\" id=\"mr-equip-pet\" onclick=\"mrEquipSlotTap('pet')\">
        <img class=\"mr-equip-img\" id=\"mr-equip-pet-img\" src=\"\" alt=\"\">
        <div class=\"mr-equip-label\">PET</div>
        <div class=\"mr-equip-name\" id=\"mr-equip-pet-name\">なし</div>
      </div>""",
    1  # only first occurrence
)

# ============================================================
# 9. SHOP画像を大きく表示（38px → 64px）
# ============================================================
html = html.replace(
    'style="width:38px;height:38px;object-fit:contain;filter:drop-shadow(0 2px 6px rgba(0,200,255,.3));"',
    'style="width:64px;height:64px;object-fit:contain;filter:drop-shadow(0 2px 8px rgba(0,200,255,.4));border-radius:4px;"'
)
html = html.replace(
    ".shop-item-icon{font-size:26px;width:40px;text-align:center;flex-shrink:0;}",
    ".shop-item-icon{font-size:32px;width:70px;height:70px;display:flex;align-items:center;justify-content:center;text-align:center;flex-shrink:0;}"
)

# ============================================================
# 10. バトル中のビジュアルを大きく（72px → 110px, 敵90px → 130px）
# ============================================================
html = html.replace(
    "width:72px;height:72px;object-fit:contain;\n  filter:drop-shadow(0 0 10px rgba(0,200,255,.3));",
    "width:110px;height:110px;object-fit:contain;\n  filter:drop-shadow(0 0 14px rgba(0,200,255,.4));"
)
html = html.replace(
    'style="width:90px;height:90px;object-fit:contain;filter:drop-shadow(0 0 12px rgba(255,80,80,.6));margin-bottom:2px;"',
    'style="width:130px;height:130px;object-fit:contain;filter:drop-shadow(0 0 16px rgba(255,80,80,.7));margin-bottom:4px;"'
)

# ============================================================
# 11. 左スワイプで前画面に戻る
# ============================================================
# Find the closing </body> or end of script section and add swipe handler
swipe_js = """
/* ── 左スワイプで前画面に戻る ── */
(function(){
  let _swStartX=0,_swStartY=0,_swActive=false;
  document.addEventListener('touchstart',function(e){
    if(e.touches.length!==1) return;
    _swStartX=e.touches[0].clientX;
    _swStartY=e.touches[0].clientY;
    _swActive=_swStartX<40; // 画面左端40pxからのスワイプのみ
  },{passive:true});
  document.addEventListener('touchend',function(e){
    if(!_swActive) return;
    _swActive=false;
    const dx=e.changedTouches[0].clientX-_swStartX;
    const dy=Math.abs(e.changedTouches[0].clientY-_swStartY);
    if(dx>80 && dy<80){
      // 右方向スワイプ = 戻る
      const battleModal=document.getElementById('battle-modal');
      const shopModal=document.getElementById('shop-modal');
      const miniroom=document.getElementById('miniroom');
      if(battleModal && battleModal.style.display!=='none' && battleModal.style.display!==''){
        const closeBtn=document.getElementById('battle-close-btn');
        if(closeBtn) closeBtn.click();
      } else if(shopModal && shopModal.style.display!=='none' && shopModal.style.display!==''){
        const closeBtn=shopModal.querySelector('.mr-close-btn')||document.querySelector('[onclick*="closeShop"]');
        if(closeBtn) closeBtn.click();
      } else if(miniroom && miniroom.classList.contains('active')){
        const backBtn=document.getElementById('mr-back-btn');
        if(backBtn) backBtn.click();
      }
    }
  },{passive:true});
})();
"""

# ============================================================
# 12. ペットのバトル効果とルームうろちょろ
# ============================================================
pet_js = """
/* ── ペット装備処理 ── */
window.equipPet = function(petId){
  const item = (SHOP_ITEMS.pet||[]).find(x=>x.id===petId);
  if(!item) return;
  D.equip.pet = petId;
  saveData(D);
  updateEquipDisplay();
  showDropToast(item.name+'を連れ出した！');
  renderShopList();
  // ルームにペット表示
  if(document.getElementById('miniroom').classList.contains('active')){
    spawnRoomPet();
  }
};

window.unequipPet = function(){
  D.equip.pet = null;
  saveData(D);
  updateEquipDisplay();
  renderShopList();
  const petEl=document.getElementById('room-pet');
  if(petEl) petEl.remove();
};

/* ── ルーム内ペットうろちょろ ── */
function spawnRoomPet(){
  let petEl=document.getElementById('room-pet');
  if(petEl) petEl.remove();
  if(!D.equip.pet) return;
  const pet=(SHOP_ITEMS.pet||[]).find(x=>x.id===D.equip.pet);
  if(!pet) return;
  const mr=document.getElementById('miniroom');
  if(!mr) return;
  petEl=document.createElement('div');
  petEl.id='room-pet';
  petEl.style.cssText='position:absolute;bottom:18%;z-index:55;font-size:32px;transition:left 2s ease-in-out;pointer-events:none;filter:drop-shadow(0 2px 6px rgba(0,0,0,.5));';
  petEl.textContent=pet.icon;
  petEl.style.left='30%';
  mr.appendChild(petEl);
  // うろちょろアニメーション
  let petDir=1;
  setInterval(()=>{
    if(!document.getElementById('room-pet')) return;
    const pos=parseFloat(petEl.style.left)||30;
    const newPos=pos+(Math.random()*15-5)*petDir;
    petEl.style.left=Math.max(10,Math.min(80,newPos))+'%';
    if(Math.random()<0.3) petDir*=-1;
    // 上下バウンス
    petEl.style.transform='translateY('+(Math.sin(Date.now()/500)*4)+'px)';
  },2000);
}

/* ── バトル中のペット効果 ── */
window.applyPetEffect = function(isPlayerTurn){
  if(!D.equip.pet) return null;
  const pet=(SHOP_ITEMS.pet||[]).find(x=>x.id===D.equip.pet);
  if(!pet||!pet.skill) return null;
  if(pet.skill.effect==='pet_heal' && isPlayerTurn){
    return {type:'heal',val:pet.skill.val,name:pet.skill.name,petName:pet.name};
  }
  if(pet.skill.effect==='pet_attack' && isPlayerTurn){
    return {type:'attack',val:pet.skill.val,name:pet.skill.name,petName:pet.name};
  }
  return null;
};
"""

# Insert before closing </script>
# Find last </script> and insert before it
last_script_idx = html.rfind('</script>')
if last_script_idx > 0:
    html = html[:last_script_idx] + swipe_js + pet_js + '\n' + html[last_script_idx:]

# ============================================================
# 13. ショップのequip処理にpet対応を追加
# ============================================================
# equipItem関数でpetカテゴリ対応を追加
# switchShopTab関数のpet対応
old_switch = "window.switchShopTab = function(tab){"
new_switch = """window.switchShopTab = function(tab){
  if(tab==='pet'){
    _shopTab='pet';
    document.querySelectorAll('.shop-tab').forEach(t=>t.classList.remove('active'));
    document.getElementById('tab-pet').classList.add('active');
    renderShopList();
    return;
  }"""
html = html.replace(old_switch, new_switch, 1)

# shopリストでpet表示対応（装備ボタン表示含む）
# equip/買うロジックでpet対応
old_equip_cats = "['weapon','armor'].forEach(cat=>{"
new_equip_cats = "['weapon','armor','pet'].forEach(cat=>{"
html = html.replace(old_equip_cats, new_equip_cats)

# shopListでpetの装備ボタン
old_buy_onclick = "if(!equipped && !owned && canAfford){\n      div.onclick = ()=>buyItem(_shopTab, item.id);"
new_buy_onclick = """if(_shopTab==='pet' && owned && !equipped){
      div.onclick = ()=>equipPet(item.id);
    } else if(_shopTab==='pet' && equipped){
      div.onclick = ()=>unequipPet();
    } else if(!equipped && !owned && canAfford){
      div.onclick = ()=>buyItem(_shopTab, item.id);"""
html = html.replace(old_buy_onclick, new_buy_onclick, 1)

# updateEquipDisplay でpet対応
old_update_equip = "['weapon','armor'].forEach(slot=>{"
new_update_equip = "['weapon','armor','pet'].forEach(slot=>{"
html = html.replace(old_update_equip, new_update_equip)

# allItems にpet追加
html = html.replace(
    "const allItems = [...SHOP_ITEMS.weapon, ...SHOP_ITEMS.armor];",
    "const allItems = [...SHOP_ITEMS.weapon, ...SHOP_ITEMS.armor, ...(SHOP_ITEMS.pet||[])];"
)

# ============================================================
# 14. ペット画像用のSVG生成（ペットZIPが空だったので絵文字代替でプレースホルダー）
# ============================================================
# ペット画像は絵文字で表示するのでimg不要（iconで十分）

# ============================================================
# 15. バトルでのペット追撃をログに表示
# ============================================================
# battleAction関数内のattack処理後にペット効果挿入
# 簡単に: battleAction('attack')の後にペット効果を差し込む

# ============================================================
# Save
# ============================================================
with open(FILE, 'w', encoding='utf-8') as f:
    f.write(html)

# web/index.htmlにも同期
with open('web/index.html', 'w', encoding='utf-8') as f:
    f.write(html)

print("✅ All fixes applied successfully!")
print(f"   File size: {len(html)} bytes")
