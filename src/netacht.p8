pico-8 cartridge // http://www.pico-8.com
version 42
__lua__
-- netacht
-- a pico-8 nethack demake

mw=48 mh=32 vw=32 vh=16
mode="title" turn=0 depth=1
roles={
 {n="valkyrie",hp=18,str=8,dex=6,con=8,ac=2,w="long sword",a="chain mail",food=900,g=20},
 {n="wizard",hp=12,str=4,dex=7,con=5,ac=0,w="quarterstaff",a="cloak",food=760,g=35,wand=1},
 {n="rogue",hp=14,str=6,dex=9,con=5,ac=1,w="dagger",a="leather",food=780,g=60},
 {n="healer",hp=16,str=4,dex=5,con=7,ac=1,w="scalpel",a="robe",food=860,g=90,pot=2},
 {n="monk",hp=15,str=7,dex=7,con=6,ac=0,w="hands",a="robe",food=820,g=5},
 {n="tourist",hp=13,str=5,dex=5,con=5,ac=0,w="dart",a="shirt",food=1100,g=160}
}
rp=1
mtdefs={
 {n="lichen",ch="f",c=11,h=3,a=1,xp=1,s=0},
 {n="newt",ch=":",c=12,h=4,a=2,xp=2,s=1},
 {n="jackal",ch="d",c=4,h=5,a=2,xp=3,s=1},
 {n="kobold",ch="k",c=3,h=6,a=3,xp=4,s=1},
 {n="goblin",ch="o",c=8,h=7,a=3,xp=5,s=1},
 {n="dwarf",ch="h",c=9,h=9,a=4,xp=8,s=1},
 {n="nymph",ch="n",c=14,h=8,a=2,xp=9,s=2},
 {n="floating eye",ch="e",c=12,h=6,a=0,xp=7,s=3},
 {n="orc captain",ch="O",c=8,h=14,a=5,xp=13,s=1},
 {n="wraith",ch="W",c=5,h=12,a=5,xp=18,s=4},
 {n="xorn",ch="X",c=13,h=18,a=6,xp=24,s=1},
 {n="minotaur",ch="H",c=4,h=28,a=8,xp=40,s=1}
}
weps={
 ["hands"]={d=3},["dagger"]={d=4},["scalpel"]={d=4},["dart"]={d=3},
 ["quarterstaff"]={d=6},["mace"]={d=6},["long sword"]={d=8},["axe"]={d=7},
 ["crysknife"]={d=10}
}
arms={["shirt"]=0,["robe"]=1,["cloak"]=1,["leather"]=2,["chain mail"]=4,["mithril"]=5}
ptn={"ruby","smoky","milky","bubbly","ochre"}
scr={"zelgo","kirje","praty","velo","tharr"}
msgs={}
best=0

function _init()
 cartdata("netacht_01")
 best=dget(0) or 0
 poke(0x5f5c,8) poke(0x5f5d,3)
 if stat(6)=="smoke" then
  make_player()
  assert(#rooms>1,"rooms")
  assert(#items>0,"items")
  assert(#mons>0,"mons")
  stop("smoke ok")
 end
end

function msg(s,c)
 add(msgs,{s=s,c=c or 7})
 while #msgs>3 do deli(msgs,1) end
end

function rr(a,b) return flr(rnd(b-a+1))+a end
function one(t) return t[rr(1,#t)] end
function sgn(v) if v<0 then return -1 elseif v>0 then return 1 end return 0 end
function dist(a,b,c,d) return abs(a-c)+abs(b-d) end
function ix(x,y) return x+y*mw end
function inb(x,y) return x>=0 and y>=0 and x<mw and y<mh end
function gt(x,y) if not inb(x,y) then return 0 end return map[ix(x,y)] or 0 end
function st(x,y,v) if inb(x,y) then map[ix(x,y)]=v end end
function pass(x,y) local v=gt(x,y) return v==1 or v==3 or v==4 or v>=5 end
function block(x,y) local v=gt(x,y) return v==0 or v==2 end

function new_item(k,x,y)
 local it={k=k,x=x,y=y,bu=rr(-1,1)}
 if k=="gold" then it.n="gold" it.q=rr(5,25)*depth return it end
 if k=="food" then it.n=one({"ration","tripe","apple","corpse"}) it.q=rr(120,320) return it end
 if k=="weapon" then it.n=one({"dagger","mace","axe","long sword"}) it.d=weps[it.n].d return it end
 if k=="armor" then it.n=one({"leather","chain mail","cloak","mithril"}) it.ac=arms[it.n] return it end
 if k=="potion" then it.id=rr(1,5) it.n=ptn[it.id].." potion" return it end
 if k=="scroll" then it.id=rr(1,5) it.n="scroll "..scr[it.id] return it end
 if k=="wand" then it.id=rr(1,4) it.n=one({"oak","bone","iron","glass"}).." wand" it.z=rr(2,5) return it end
 it.n="strange gem" return it
end

function place_item(k,x,y)
 if not x then x,y=freepos() end
 add(items,new_item(k,x,y))
end

function freepos()
 for z=1,400 do
  local r=one(rooms)
  local x=rr(r.x,r.x+r.w-1) local y=rr(r.y,r.y+r.h-1)
  if pass(x,y) and not mon_at(x,y) and not (pl and pl.x==x and pl.y==y) then return x,y end
 end
 return rooms[1].x+1,rooms[1].y+1
end

function overlap(x,y,w,h)
 for r in all(rooms) do
  if x-1<r.x+r.w+1 and x+w+1>r.x-1 and y-1<r.y+r.h+1 and y+h+1>r.y-1 then return true end
 end
 return false
end

function carve_room(r)
 for y=r.y,r.y+r.h-1 do
  for x=r.x,r.x+r.w-1 do st(x,y,1) end
 end
end

function carve_corr(x1,y1,x2,y2)
 local x=x1 local y=y1
 while x~=x2 do st(x,y,4) x+=sgn(x2-x) end
 while y~=y2 do st(x,y,4) y+=sgn(y2-y) end
 st(x,y,4)
end

function walls()
 for y=1,mh-2 do
  for x=1,mw-2 do
   if gt(x,y)==0 then
    for yy=-1,1 do for xx=-1,1 do
     local v=gt(x+xx,y+yy)
     if v==1 or v==4 or v>=5 then st(x,y,2) end
    end end
   end
  end
 end
 for y=1,mh-2 do
  for x=1,mw-2 do
   if gt(x,y)==4 then
    for yy=-1,1 do for xx=-1,1 do
     if gt(x+xx,y+yy)==1 and rnd()<.04 then st(x,y,3) end
    end end
   end
  end
 end
end

function gen_level(d)
 depth=d map={} seen={} vis={} traps={} items={} mons={} rooms={}
 for i=0,mw*mh-1 do map[i]=0 seen[i]=0 vis[i]=0 end
 for a=1,80 do
  local w=rr(4,10) local h=rr(3,7)
  local x=rr(2,mw-w-3) local y=rr(2,mh-h-3)
  if not overlap(x,y,w,h) then
   local r={x=x,y=y,w=w,h=h,t="room"}
   add(rooms,r) carve_room(r)
   if #rooms>=rr(11,16) then break end
  end
 end
 if #rooms<2 then gen_level(d) return end
 for i=2,#rooms do
  local a=rooms[i-1] local b=rooms[i]
  carve_corr(a.x+a.w\2,a.y+a.h\2,b.x+b.w\2,b.y+b.h\2)
 end
 walls()
 for i=2,#rooms do
  local r=rooms[i]
  if rnd()<.38 then
   r.t=one({"shop","temple","fountain","grave","trap","zoo","store"})
   if r.t=="shop" or r.t=="store" then for y=r.y,r.y+r.h-1 do for x=r.x,r.x+r.w-1 do st(x,y,9) end end end
   if r.t=="temple" then st(r.x+r.w\2,r.y+r.h\2,7) end
   if r.t=="fountain" then st(r.x+r.w\2,r.y+r.h\2,8) end
   if r.t=="trap" then for n=1,rr(3,6) do add_trap() end end
  end
 end
 local a=rooms[1] pl.x=a.x+a.w\2 pl.y=a.y+a.h\2 st(pl.x,pl.y,5)
 local b=rooms[#rooms] downx=b.x+b.w\2 downy=b.y+b.h\2 st(downx,downy,6)
 if d==12 then place_item("amulet",downx,downy) end
 for i=1,7+d do place_item(one({"gold","food","weapon","armor","potion","scroll","wand","gem"})) end
 for i=1,5+d*2 do add_mon() end
 for i=1,3+d\2 do add_trap() end
 upd_vis()
 msg("welcome to level "..d,11)
end

function add_trap()
 local x,y=freepos()
 traps[ix(x,y)]={x=x,y=y,t=one({"pit","arrow","sleep","teleport","poly","rust"}),seen=false}
end

function add_mon()
 local x,y=freepos()
 local maxm=mid(1,depth+3,#mtdefs)
 local d=mtdefs[rr(1,maxm)]
 add(mons,{n=d.n,ch=d.ch,c=d.c,x=x,y=y,h=d.h+depth,a=d.a+depth\3,xp=d.xp,s=d.s,awake=false})
end

function make_player()
 local r=roles[rp]
 pl={x=1,y=1,role=r.n,maxhp=r.hp,hp=r.hp,str=r.str,dex=r.dex,con=r.con,
     ac=r.ac,baseac=r.ac,xp=0,lev=1,g=r.g,hunger=r.food,inv={},w=r.w,a=r.a,
     prayer=0,stun=0,hasamu=false}
 add(pl.inv,{k="weapon",n=r.w,d=weps[r.w].d})
 add(pl.inv,{k="armor",n=r.a,ac=arms[r.a]})
 add(pl.inv,new_item("food"))
 if r.wand then add(pl.inv,new_item("wand")) end
 if r.pot then for i=1,r.pot do add(pl.inv,new_item("potion")) end end
 turn=0 gen_level(1) mode="play"
 msg("you are a "..r.n,10)
end

function mon_at(x,y)
 for m in all(mons) do if m.x==x and m.y==y then return m end end
end

function item_at(x,y)
 local t={}
 for it in all(items) do if it.x==x and it.y==y then add(t,it) end end
 return t
end

function los(x0,y0,x1,y1)
 local dx=abs(x1-x0) local dy=abs(y1-y0)
 local sx=sgn(x1-x0) local sy=sgn(y1-y0)
 local err=dx-dy local x=x0 local y=y0
 while true do
  if x==x1 and y==y1 then return true end
  if not (x==x0 and y==y0) and block(x,y) then return false end
  local e2=err*2
  if e2>-dy then err-=dy x+=sx end
  if e2<dx then err+=dx y+=sy end
 end
end

function upd_vis()
 for i=0,mw*mh-1 do vis[i]=0 end
 for y=pl.y-8,pl.y+8 do
  for x=pl.x-12,pl.x+12 do
   if inb(x,y) and dist(pl.x,pl.y,x,y)<=12 and los(pl.x,pl.y,x,y) then
    local k=ix(x,y) vis[k]=1 seen[k]=1
    local tr=traps[k] if tr and rnd()<.07+pl.dex/80 then tr.seen=true end
   end
  end
 end
 for m in all(mons) do if vis[ix(m.x,m.y)]==1 then m.awake=true end end
end

function tile_ch(v)
 if v==0 then return " " end
 if v==1 or v==9 then return "." end
 if v==2 then return "#" end
 if v==3 then return "+" end
 if v==4 then return "#" end
 if v==5 then return "<" end
 if v==6 then return ">" end
 if v==7 then return "_" end
 if v==8 then return "{" end
 return "."
end

function tile_col(v,lit)
 if not lit then return 5 end
 if v==1 then return 6 end
 if v==9 then return 10 end
 if v==2 then return 5 end
 if v==3 then return 9 end
 if v==4 then return 13 end
 if v==5 or v==6 then return 7 end
 if v==7 then return 11 end
 if v==8 then return 12 end
 return 6
end

function obj_ch(it)
 if it.k=="gold" then return "$",10 end
 if it.k=="food" then return "%",11 end
 if it.k=="potion" then return "!",14 end
 if it.k=="scroll" then return "?",7 end
 if it.k=="wand" then return "/",13 end
 if it.k=="weapon" then return ")",6 end
 if it.k=="armor" then return "[",12 end
 if it.k=="amulet" then return "\"",10 end
 return "*",9
end

function _update()
 if mode=="title" then up_title()
 elseif mode=="play" then up_play()
 elseif mode=="inv" then up_inv()
 elseif mode=="help" then if btnp(4) or btnp(5) then mode=oldmode or "title" end
 elseif mode=="dead" or mode=="win" then if btnp(4) or btnp(5) then mode="title" end
 end
end

function up_title()
 if btnp(0) then rp=max(1,rp-1) end
 if btnp(1) then rp=min(#roles,rp+1) end
 if btnp(4) then make_player() end
 if btnp(5) then oldmode="title" mode="help" end
end

function up_play()
 local dx=0 local dy=0
 if btnp(0) then dx=-1 elseif btnp(1) then dx=1 elseif btnp(2) then dy=-1 elseif btnp(3) then dy=1 end
 if dx~=0 or dy~=0 then try_move(dx,dy) return end
 if btnp(4) then act() return end
 if btnp(5) then sel=1 mode="inv" end
end

function spend()
 turn+=1
 if pl.stun>0 then pl.stun-=1 end
 pl.hunger-=1
 if pl.hunger<80 and turn%8==0 then hurt(rr(1,3),"starvation") end
 move_mons()
 upd_vis()
 if pl.hp<pl.maxhp and turn%18==0 and pl.hunger>120 then pl.hp+=1 end
 if pl.xp>=pl.lev*12 then pl.lev+=1 pl.maxhp+=rr(3,6) pl.hp=pl.maxhp pl.str+=1 msg("you feel more experienced",11) end
end

function try_move(dx,dy)
 if pl.stun>0 and rnd()<.35 then dx=rr(-1,1) dy=rr(-1,1) end
 local x=pl.x+dx local y=pl.y+dy
 local m=mon_at(x,y)
 if m then attack(m) spend() return end
 if pass(x,y) then
  pl.x=x pl.y=y
  local tr=traps[ix(x,y)]
  if tr and not tr.done then trigger_trap(tr) end
  spend()
 end
end

function act()
 local v=gt(pl.x,pl.y)
 local its=item_at(pl.x,pl.y)
 if #its>0 then pickup(its) spend() return end
 if v==6 then gen_level(depth+1) spend() return end
 if v==5 then
  if depth==1 and pl.hasamu then mode="win" dset(0,max(best,pl.g+pl.xp*10)) return end
  gen_level(max(1,depth-1)) spend() return
 end
 if v==7 then pray() spend() return end
 if v==8 then drink_fountain() spend() return end
 search() spend()
end

function pickup(its)
 for it in all(its) do
  if it.k=="gold" then pl.g+=it.q msg("picked up "..it.q.." gold",10) del(items,it)
  elseif it.k=="amulet" then pl.hasamu=true msg("you have yendor!",10) del(items,it)
  elseif #pl.inv<10 then add(pl.inv,it) msg("picked up "..it.n,7) del(items,it)
  else msg("pack is full",8) end
 end
end

function search()
 local found=false
 for yy=-1,1 do for xx=-1,1 do
  local tr=traps[ix(pl.x+xx,pl.y+yy)]
  if tr and not tr.seen and rnd()<.35+pl.dex/30 then tr.seen=true found=true end
 end end
 if found then msg("you find a trap",10) else msg("you search",5) end
end

function trigger_trap(tr)
 tr.seen=true tr.done=true
 if tr.t=="pit" then msg("you fall into a pit!",8) hurt(rr(2,7),"pit") end
 if tr.t=="arrow" then msg("an arrow shoots out!",8) hurt(rr(1,6),"arrow trap") end
 if tr.t=="sleep" then msg("sleep gas!",13) pl.stun=rr(3,7) end
 if tr.t=="teleport" then msg("you teleport",13) pl.x,pl.y=freepos() end
 if tr.t=="poly" then msg("you feel different",14) pl.str=mid(3,pl.str+rr(-2,3),12) end
 if tr.t=="rust" then msg("your armor rusts",4) pl.ac=max(0,pl.ac-1) end
end

function attack(m)
 local hit=rr(1,20)+pl.dex+pl.lev
 if hit>8+depth then
  local wd=weps[pl.w] and weps[pl.w].d or 3
  local dm=rr(1,wd)+pl.str\3
  if m.s==3 and rnd()<.3 then pl.stun=rr(2,5) msg("the eye freezes you",12) end
  m.h-=dm msg("you hit "..m.n.." "..dm,7)
  if m.h<=0 then
   msg("you kill "..m.n,11) pl.xp+=m.xp del(mons,m)
   if rnd()<.28 then place_item("food",m.x,m.y) end
  end
 else msg("you miss "..m.n,5) end
end

function move_mons()
 for m in all(mons) do
  if m.h>0 then
   local dx=0 local dy=0
   if dist(m.x,m.y,pl.x,pl.y)==1 then mon_hit(m)
   else
    if m.awake or dist(m.x,m.y,pl.x,pl.y)<7 then
     dx=sgn(pl.x-m.x) dy=sgn(pl.y-m.y)
     if abs(pl.x-m.x)>abs(pl.y-m.y) then dy=0 else dx=0 end
    elseif rnd()<.25 then dx=rr(-1,1) dy=rr(-1,1) end
    local nx=m.x+dx local ny=m.y+dy
    if pass(nx,ny) and not mon_at(nx,ny) and not (pl.x==nx and pl.y==ny) then m.x=nx m.y=ny end
   end
  end
 end
end

function mon_hit(m)
 local hit=rr(1,20)+m.a
 if hit>10+pl.ac+pl.dex\3 then
  local dm=max(1,rr(1,m.a+2)-pl.ac\2)
  if m.s==2 and #pl.inv>0 and rnd()<.18 then local it=pl.inv[#pl.inv] deli(pl.inv,#pl.inv) msg(m.n.." steals "..it.n,14) return end
  if m.s==4 and rnd()<.25 then pl.lev=max(1,pl.lev-1) msg("life drains away",13) end
  hurt(dm,m.n)
 else
  if vis[ix(m.x,m.y)]==1 then msg(m.n.." misses",5) end
 end
end

function hurt(n,why)
 pl.hp-=n
 if pl.hp<=0 then death(why) else msg("ouch "..n.." hp",8) end
end

function death(why)
 mode="dead" cause=why
 if pl.g>best then dset(0,pl.g) best=pl.g end
end

function pray()
 if turn<pl.prayer then msg("the gods are silent",5) return end
 pl.prayer=turn+220
 if pl.hunger<250 then pl.hunger+=500 msg("manna fills you",11)
 elseif pl.hp<pl.maxhp then pl.hp=pl.maxhp msg("you are healed",11)
 else pl.str+=1 msg("you feel blessed",11) end
end

function drink_fountain()
 local r=rr(1,5)
 if r==1 then pl.hp=min(pl.maxhp,pl.hp+rr(4,10)) msg("cool water heals",12)
 elseif r==2 then add_mon() msg("a water demon appears",8)
 elseif r==3 then place_item("gem",pl.x,pl.y) msg("something glitters",10)
 elseif r==4 then pl.stun=rr(3,6) msg("the water was odd",13)
 else msg("the fountain dries up",5) st(pl.x,pl.y,1) end
end

function up_inv()
 if btnp(5) then mode="play" return end
 local n=#pl.inv+2
 if btnp(2) then sel-=1 if sel<1 then sel=n end end
 if btnp(3) then sel+=1 if sel>n then sel=1 end end
 if (btnp(0) or btnp(1)) and sel<=#pl.inv then
  drop_item(sel)
  sel=min(sel,#pl.inv+2)
  mode="play" spend()
  return
 end
 if btnp(4) then
  if sel<=#pl.inv then use_item(pl.inv[sel],sel)
  elseif sel==#pl.inv+1 then pray()
  else oldmode="inv" mode="help" return end
  mode="play" spend()
 end
end

function drop_item(i)
 local it=deli(pl.inv,i)
 if not it then return end
 if it.k=="weapon" and pl.w==it.n then pl.w="hands" end
 if it.k=="armor" and pl.a==it.n then pl.a="shirt" pl.ac=pl.baseac end
 it.x=pl.x it.y=pl.y
 add(items,it)
 msg("dropped "..it.n,5)
end

function use_item(it,i)
 if it.k=="weapon" then pl.w=it.n msg("wielding "..it.n,10) return end
 if it.k=="armor" then pl.a=it.n pl.ac=pl.baseac+(it.ac or 0) msg("wearing "..it.n,10) return end
 if it.k=="food" then pl.hunger+=it.q msg("you eat "..it.n,11) deli(pl.inv,i) return end
 if it.k=="potion" then quaff(it) deli(pl.inv,i) return end
 if it.k=="scroll" then read_scroll(it) deli(pl.inv,i) return end
 if it.k=="wand" then zap(it) it.z-=1 if it.z<=0 then msg("the wand crumbles",5) deli(pl.inv,i) end return end
 if it.k=="gem" then pl.g+=50 msg("you appraise the gem",10) deli(pl.inv,i) return end
 msg("nothing happens",5)
end

function quaff(it)
 if it.id==1 then pl.hp=min(pl.maxhp,pl.hp+rr(8,18)) msg("you feel better",11)
 elseif it.id==2 then pl.dex+=1 msg("you feel quick",11)
 elseif it.id==3 then pl.str+=1 msg("you feel strong",11)
 elseif it.id==4 then hurt(rr(3,10),"sickness")
 else pl.stun=rr(4,8) msg("you reel",13) end
end

function read_scroll(it)
 if it.id==1 then msg("your pack is identified",11)
 elseif it.id==2 then pl.x,pl.y=freepos() msg("you teleport",13)
 elseif it.id==3 then if pl.w and weps[pl.w] then weps[pl.w].d+=1 end msg("your weapon glows",10)
 elseif it.id==4 then for i=0,mw*mh-1 do seen[i]=1 end msg("the level is revealed",10)
 else for m in all(mons) do if dist(m.x,m.y,pl.x,pl.y)<6 then m.awake=false end end msg("monsters hesitate",12) end
end

function zap(it)
 local near=nil local bd=99
 for m in all(mons) do local d=dist(pl.x,pl.y,m.x,m.y) if d<bd and d<9 then near=m bd=d end end
 if not near then msg("the wand buzzes",5) return end
 if it.id==1 then near.h-=rr(8,18) msg("bolt strikes "..near.n,10)
 elseif it.id==2 then near.h-=rr(12,24) msg("fire burns "..near.n,9)
 elseif it.id==3 then st(near.x,near.y,4) msg("rock turns to dust",13)
 else local d=one(mtdefs) near.n=d.n near.ch=d.ch near.c=d.c near.h=d.h msg("it changes shape",14) end
 if near.h<=0 then msg(near.n.." dies",11) pl.xp+=near.xp del(mons,near) end
end

function _draw()
 cls(0)
 if mode=="title" then draw_title()
 elseif mode=="play" then draw_game()
 elseif mode=="inv" then draw_game() draw_inv()
 elseif mode=="help" then draw_help()
 elseif mode=="dead" then draw_end(false)
 elseif mode=="win" then draw_end(true) end
end

function draw_title()
 print("netacht",50,10,10)
 print("a pico-8 nethack demake",20,18,6)
 local r=roles[rp]
 rect(16,36,112,84,5)
 print("< "..r.n.." >",36,42,11)
 print("hp "..r.hp.." str "..r.str.." dex "..r.dex,26,52,7)
 print("gear "..r.w,22,62,6)
 print("best "..best,44,74,10)
 print("o start  x help",30,104,7)
end

function draw_corr(sx,sy,x,y,co)
 local px=sx*4 local py=13+sy*6
 rectfill(px+1,py+2,px+2,py+3,co)
 if pass(x-1,y) then rectfill(px,py+2,px+1,py+3,co) end
 if pass(x+1,y) then rectfill(px+2,py+2,px+3,py+3,co) end
 if pass(x,y-1) then rectfill(px+1,py,px+2,py+2,co) end
 if pass(x,y+1) then rectfill(px+1,py+3,px+2,py+5,co) end
end

function draw_game()
 rectfill(0,0,127,11,1)
 print("dl"..depth.." hp"..pl.hp.."/"..pl.maxhp.." ac"..pl.ac.." xp"..pl.xp.." $"..pl.g,1,1,7)
 local hs="satiated" if pl.hunger<500 then hs="hungry" end if pl.hunger<250 then hs="weak" end if pl.hunger<100 then hs="faint" end
 print(pl.role.." "..hs.." "..pl.w,1,7,6)
 local cx=mid(0,pl.x-vw\2,mw-vw) local cy=mid(0,pl.y-vh\2,mh-vh)
 for sy=0,vh-1 do
  for sx=0,vw-1 do
   local x=cx+sx local y=cy+sy local k=ix(x,y)
   if seen[k]==1 then
    local lit=vis[k]==1 local ch=tile_ch(gt(x,y)) local co=tile_col(gt(x,y),lit) local over=false
    local tr=traps[k]
    if tr and tr.seen and lit then ch="^" co=8 over=true end
    if lit then
     local its=item_at(x,y)
     if #its>0 then ch,co=obj_ch(its[#its]) over=true end
     local m=mon_at(x,y)
     if m then ch=m.ch co=m.c over=true end
    end
    local tv=gt(x,y)
    if tv==2 and not over then
     rectfill(sx*4,13+sy*6,sx*4+3,18+sy*6,co)
    elseif tv==4 and not over then
     draw_corr(sx,sy,x,y,co)
    else
     print(ch,sx*4,13+sy*6,co)
    end
   end
  end
 end
 print("@",(pl.x-cx)*4,13+(pl.y-cy)*6,15)
 rectfill(0,109,127,127,0)
 for i=1,#msgs do print(msgs[i].s,1,103+i*6,msgs[i].c) end
end

function draw_inv()
 rectfill(10,18,118,108,0)
 rect(10,18,118,108,7)
 print("pack",52,23,10)
 local y=31
 for i=1,#pl.inv do
  local it=pl.inv[i] local mark=i==sel and ">" or " "
  local s=mark..it.n
  if it.z then s=s.."["..it.z.."]" end
  local eq=(it.k=="weapon" and pl.w==it.n) or (it.k=="armor" and pl.a==it.n)
  local co=eq and 10 or 6
  if i==sel then co=eq and 14 or 11 end
  print(sub(s,1,25),16,y,co) y+=6
 end
 print((sel==#pl.inv+1 and ">" or " ").."pray",16,y,sel==#pl.inv+1 and 11 or 6) y+=6
 print((sel==#pl.inv+2 and ">" or " ").."help",16,y,sel==#pl.inv+2 and 11 or 6)
 print("o use  <> drop  x close",16,103,5)
end

function draw_help()
 cls(0)
 print("netacht commands",31,10,10)
 print("arrows: move/attack",8,25,7)
 print("o: pickup stairs altar",8,34,7)
 print("o also searches/rests",8,43,6)
 print("x: inventory/actions",8,52,7)
 print("in pack: up/down,o use",8,61,6)
 print("left/right drops item",8,70,6)
 print("find yendor on dl12",8,82,10)
 print("return to dl1 to win",8,91,10)
 print("rooms, traps, shops,",8,106,5)
 print("hunger and gods vary",8,115,5)
 print("o/x back",48,121,7)
end

function draw_end(win)
 cls(0)
 if win then
  print("ascended!",46,24,10)
  print("you escaped with",32,42,7)
  print("the amulet of yendor",25,51,11)
  print("score "..(pl.g+pl.xp*10),43,68,10)
 else
  print("you died",48,28,8)
  print("killed by "..cause,20,45,7)
  print("depth "..depth.." gold "..pl.g,30,61,10)
 end
 print("o/x title",45,100,6)
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
