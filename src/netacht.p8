pico-8 cartridge // http://www.pico-8.com
version 43
__lua__
-- netacht
-- a pico-8 nethack demake

mw=48 mh=32
mode="title" turn=0 depth=1
rdat="valkyrie,18,8,6,2,long sword,chain mail,900,20,0,0|wizard,12,4,7,5,quarterstaff,cloak,760,35,1,0|rogue,14,6,9,5,dagger,leather,780,60,0,0|healer,16,4,5,3,scalpel,robe,860,90,0,2|monk,15,7,7,4,hands,robe,820,5,0,0|tourist,13,5,5,5,dart,shirt,1100,160,0,0"
rp=1
mdat="lichen,f,11,3,1,1,0|newt,:,12,4,2,2,1|jackal,d,4,5,2,3,1|kobold,k,3,6,3,4,1|goblin,o,8,7,3,5,1|dwarf,h,9,9,4,8,1|nymph,n,14,8,2,9,2|floating eye,e,12,6,0,7,3|orc captain,O,8,14,5,13,1|wraith,W,5,12,5,18,4|xorn,X,13,18,6,24,1|minotaur,H,4,28,8,40,1"
weps={
 ["hands"]={d=3},["dagger"]={d=4},["scalpel"]={d=4},["dart"]={d=3},
 ["quarterstaff"]={d=6},["mace"]={d=6},["long sword"]={d=8},["axe"]={d=7}
}
arms={["shirt"]=0,["robe"]=1,["cloak"]=1,["leather"]=2,["chain mail"]=4,["mithril"]=5}
ptn=split"ruby,smoky,milky,bubbly,ochre,purple,swirly"
scr=split"zelgo,kirje,praty,velo,tharr,elbib"
pn=split"healing,speed,gain ability,sickness,confusion,hallucination,polymorph"
sn=split"identify,teleport,enchant,mapping,scare,remove curse"
wn=split"missile,fire,digging,polymorph,teleport"
tn={"stone","floor","wall","door","corridor","stairs up","stairs down","altar","fountain","floor"}
tc={" ",".","#","+","#","<",">","_","{","."}
tco={5,5,5,9,13,7,7,11,12,5}
oc={gold="$",food="%",potion="!",scroll="?",wand="/",weapon=")",armor="[",amulet="\""}
oco={gold=10,food=11,potion=14,scroll=7,wand=13,weapon=6,armor=12,amulet=10}
msgs={}
mus=-2

-- boot cartdata, input repeat, and smoke checks
function _init()
 defs()
 poke(0x5f5c,8) poke(0x5f5d,3)
 if stat(6)=="smoke" then
  make_player()
  assert(#rooms>1,"rooms")
  assert(stair_ok(),"stairs")
  assert(not bad_corr(),"corr")
  assert(#items>0,"items")
  assert(#mons>0,"mons")
  assert(traps_ok(),"traps")
  stop("smoke ok")
 end
 bgm(0)
end

function defs()
 roles={}
 for r in all(split(rdat,"|")) do
  local a=split(r)
  add(roles,{n=a[1],hp=a[2],str=a[3],dex=a[4],ac=a[5],w=a[6],a=a[7],food=a[8],g=a[9],wand=a[10],pot=a[11]})
 end
 mtdefs={}
 for r in all(split(mdat,"|")) do
  local a=split(r)
  add(mtdefs,{n=a[1],ch=a[2],c=a[3],h=a[4],a=a[5],xp=a[6],s=a[7]})
 end
end

-- add a message to the rolling message log
function msg(s,c)
 add(msgs,{s=s,c=c or 7})
 while #msgs>3 do deli(msgs,1) end
end

-- switch background music without restarting the current loop
function bgm(n)
 if mus==n then return end
 mus=n
 if n<0 then music(-1,600) else music(n,900,12) end
end

-- random integer in inclusive range
function rr(a,b) return flr(rnd(b-a+1))+a end
-- choose a random table entry
function one(t) return t[rr(1,#t)] end
-- sign of a number as -1, 0, or 1
function sgn(v) return v<0 and -1 or v>0 and 1 or 0 end
-- manhattan distance between two cells
function dist(a,b,c,d) return abs(a-c)+abs(b-d) end
-- true when two cells touch, including diagonals
function adj(a,b,c,d) return max(abs(a-c),abs(b-d))==1 end
-- prevent diagonal movement through blocked corners
function clear_diag(a,b,c,d) return a==c or b==d or (pass(a,d) and pass(c,b)) end
-- convert x,y to flat map index
function ix(x,y) return x+y*mw end
-- true when a cell is inside dungeon bounds
function inb(x,y) return x>=0 and y>=0 and x<mw and y<mh end
-- read dungeon tile, treating out-of-bounds as solid
function gt(x,y) if not inb(x,y) then return 0 end return map[ix(x,y)] or 0 end
-- write dungeon tile inside bounds
function st(x,y,v) if inb(x,y) then map[ix(x,y)]=v end end
-- true when actors can enter a tile
function pass(x,y) local v=gt(x,y) return v>3 or v==1 end
-- true when a tile blocks sight and bolts
function block(x,y) local v=gt(x,y) return v<4 and v~=1 end
-- recalculate armor class from worn armor state
function calc_ac() pl.ac=pl.baseac-(pl.a and max(0,pl.a.ac-pl.a.r) or 0) end

function price(it)
 return 20+depth*5+(it.k=="wand" and 40 or it.k=="armor" and 30 or it.k=="weapon" and 20 or 0)
end

-- display item name, applying identification and rust
function iname(it)
 local s=it.n
 if it.k=="potion" then s=knp[it.id] and "potion of "..pn[it.id] or it.n end
 if it.k=="scroll" then s=kns[it.id] and "scroll of "..sn[it.id] or it.n end
 if it.k=="wand" then s=knw[it.id] and "wand of "..wn[it.id] or it.n end
 if it.k=="armor" and it.r>0 then s="rusty "..it.n end
 if it.bk then local b=it.bu s=(b<0 and "cursed " or b>0 and "blessed " or "uncursed ")..s end
 if it.unp then s=s.." $"..it.p end
 return s
end

function known(it,set)
 if set then it.bk=true end
 if it.k=="potion" then if set then knp[it.id]=true end return knp[it.id] end
 if it.k=="scroll" then if set then kns[it.id]=true end return kns[it.id] end
 if it.k=="wand" then if set then knw[it.id]=true end return knw[it.id] end
 return true
end

-- add a passable tile to the pathfinding frontier
function path_add(qx,qy,x,y,d)
 local k=ix(x,y)
 if (pass(x,y) or doorpath and gt(x,y)==3) and not pd[k] then pd[k]=d add(qx,x) add(qy,y) end
end

-- build distances from the player for monster chasing
function pathmap()
 pd={} local qx={pl.x} local qy={pl.y} local qi=1
 pd[ix(pl.x,pl.y)]=0
 while qi<=#qx do
  local x=qx[qi] local y=qy[qi] local d=pd[ix(x,y)]+1
  qi+=1
  path_add(qx,qy,x+1,y,d) path_add(qx,qy,x-1,y,d)
  path_add(qx,qy,x,y+1,d) path_add(qx,qy,x,y-1,d)
 end
end

function stair_ok()
 local r=rooms[1]
 pl.x=r.x+r.w\2 pl.y=r.y+r.h\2 doorpath=true pathmap() doorpath=false
 for r in all(rooms) do
  if not pd[ix(r.x+r.w\2,r.y+r.h\2)] then return false end
 end
 return true
end

-- create an item of kind k for the current depth
function new_item(k,x,y)
 local it={k=k,x=x,y=y,bu=rr(-1,1)}
 if k=="gold" then it.n="gold" it.q=rr(5,25)*depth return it end
 if k=="food" then it.n=one({"ration","tripe","apple","corpse"}) it.q=rr(80,220) return it end
 if k=="weapon" then it.n=one({"dagger","mace","axe","long sword"}) it.d=weps[it.n].d return it end
 if k=="armor" then it.n=one({"leather","chain mail","cloak","mithril"}) it.ac=arms[it.n] it.r=0 return it end
 if k=="potion" then it.id=rr(1,#pn) it.n=ptn[it.id].." potion" return it end
 if k=="scroll" then it.id=rr(1,#sn) it.n="scroll "..scr[it.id] return it end
 if k=="wand" then it.id=rr(1,#wn) it.n=one({"oak","bone","iron","glass","zinc"}).." wand" it.z=rr(0,5) return it end
 it.n="strange gem" return it
end

-- place a generated item on the map
function place_item(k,x,y)
 if not x then x,y=freepos() end
 local it=new_item(k,x,y)
 if gt(x,y)==9 and it.k~="gold" then it.unp=true it.p=price(it) end
 add(items,it)
end

-- save current level state before changing depth
function save_level()
 levels[depth]={map=map,seen=seen,vis=vis,traps=traps,items=items,mons=mons,
  rooms=rooms,upx=upx,upy=upy,downx=downx,downy=downy}
end

-- restore a cached level or generate it if unseen
function load_level(d,dir)
 save_level()
 local l=levels[d]
 if l then
  depth=d map=l.map seen=l.seen vis=l.vis traps=l.traps items=l.items mons=l.mons
  rooms=l.rooms upx=l.upx upy=l.upy downx=l.downx downy=l.downy
  if dir>0 then pl.x=upx pl.y=upy else pl.x=downx pl.y=downy end
  upd_vis() msg("return to level "..d,11)
 else
  gen_level(d,dir)
 end
end

-- weighted random loot table
function loot_kind()
 local r=rnd()
 if r<.24 then return "gold" end
 if r<.42 then return "gem" end
 if r<.56 then return "food" end
 if r<.68 then return "weapon" end
 if r<.78 then return "armor" end
 if r<.88 then return "potion" end
 if r<.96 then return "scroll" end
 return depth>3 and "wand" or "gold"
end

-- find an open room cell, optionally away from view
function freepos(far)
 for z=1,400 do
  local r=one(rooms)
  local x=rr(r.x,r.x+r.w-1) local y=rr(r.y,r.y+r.h-1)
  if pass(x,y) and not mon_at(x,y) and not (pl and pl.x==x and pl.y==y) and (not far or (vis[ix(x,y)]~=1 and dist(pl.x,pl.y,x,y)>8)) then return x,y end
 end
 return rooms[1].x+1,rooms[1].y+1
end

function traps_ok()
 for i=0,mw*mh-1 do
  local tr=traps[i]
  if tr and bydoor(tr.x,tr.y) then return false end
 end
 return true
end

-- test whether a candidate room overlaps existing rooms
function overlap(x,y,w,h)
 for r in all(rooms) do
  if x-1<r.x+r.w+1 and x+w+1>r.x-1 and y-1<r.y+r.h+1 and y+h+1>r.y-1 then return true end
 end
 return false
end

-- carve a rectangular room into the map
function carve_room(r)
 for y=r.y,r.y+r.h-1 do
  for x=r.x,r.x+r.w-1 do st(x,y,1) end
 end
end

function corr_st(x,y) if gt(x,y)~=3 then st(x,y,4) end end

-- carve an l-shaped corridor between points
function carve_corr(x1,y1,x2,y2)
 local x=x1 local y=y1
 while x~=x2 do corr_st(x,y) x+=sgn(x2-x) end
 while y~=y2 do corr_st(x,y) y+=sgn(y2-y) end
 corr_st(x,y)
end

-- true when an orthogonal neighbor is already a door
function bydoor(x,y)
 return gt(x+1,y)==3 or gt(x-1,y)==3 or gt(x,y+1)==3 or gt(x,y-1)==3
end

function co(v) return v>2 and v<5 end
function ri(v) return v==1 or v>4 end

-- reject two-wide corridors and malformed door mouths
function bad_corr()
 for y=1,mh-2 do
  for x=1,mw-2 do
   local v=gt(x,y)
   if co(v) and co(gt(x+1,y)) and co(gt(x,y+1)) and co(gt(x+1,y+1)) then return true end
   if v==3 then
    local l=gt(x-1,y) local r=gt(x+1,y) local u=gt(x,y-1) local d=gt(x,y+1)
    if not (ri(l) and r==4 or ri(r) and l==4 or ri(u) and d==4 or ri(d) and u==4) then return true end
   end
  end
 end
end

-- try a candidate room-edge door position
function door_try(r,dx,dy,i)
 local x,y
 if dx~=0 then
  x=dx>0 and r.x+r.w or r.x-1 y=r.y+i
 else
  x=r.x+i y=dy>0 and r.y+r.h or r.y-1
 end
 if inb(x,y) and gt(x,y)==0 and gt(x-dx,y-dy)==1 and not bydoor(x,y) then return x,y end
end

-- find a valid door on the room edge facing dx,dy
function door_pos(r,dx,dy)
 local n=dx~=0 and r.h or r.w
 for z=1,20 do
  local x,y=door_try(r,dx,dy,rr(0,n-1))
  if x then return x,y end
 end
 for i=0,n-1 do
  local x,y=door_try(r,dx,dy,i)
  if x then return x,y end
 end
end

-- join rooms using room-edge doorway candidates
function join_rooms(a,b)
 local dx=0 local dy=0
 if b.x>a.x+a.w-1 then dx=1
 elseif b.y+b.h-1<a.y then dy=-1
 elseif b.x+b.w-1<a.x then dx=-1
 else dy=1 end
 local x1,y1=door_pos(a,dx,dy)
 local x2,y2=door_pos(b,-dx,-dy)
 if not x1 or not x2 then return end
 carve_corr(x1+dx,y1+dy,x2-dx,y2-dy)
 st(x1,y1,3) st(x2,y2,3)
end

-- derive visible wall tiles from carved space
function walls()
 for y=1,mh-2 do
  for x=1,mw-2 do
   if gt(x,y)==0 then
    for yy=-1,1 do for xx=-1,1 do
     local v=gt(x+xx,y+yy)
     if v==1 or v==3 or v==4 or v>=5 then st(x,y,2) end
    end end
   end
  end
 end
end

-- generate a fresh dungeon level and populate it
function gen_level(d,dir)
 depth=d map={} seen={} vis={} traps={} items={} mons={} rooms={}
 for i=0,mw*mh-1 do map[i]=0 seen[i]=0 vis[i]=0 end
 for a=1,80 do
  local w=rr(4,10) local h=rr(3,7)
  local x=rr(2,mw-w-3) local y=rr(2,mh-h-3)
  if not overlap(x,y,w,h) then
   local r={x=x,y=y,w=w,h=h}
   add(rooms,r) carve_room(r)
   if #rooms>=rr(11,16) then break end
  end
 end
 if #rooms<2 then gen_level(d,dir) return end
 for i=2,#rooms do
  local a=rooms[i-1] local b=rooms[i]
  join_rooms(a,b)
 end
 if not stair_ok() or bad_corr() then gen_level(d,dir) return end
 walls()
 for i=2,#rooms do
  local r=rooms[i]
  if rnd()<.27 then
   local t=one({"shop","temple","fountain","trap","store"})
   if t=="shop" or t=="store" then
    for y=r.y,r.y+r.h-1 do for x=r.x,r.x+r.w-1 do st(x,y,9) end end
    for n=1,rr(2,4) do place_item(loot_kind(),rr(r.x,r.x+r.w-1),rr(r.y,r.y+r.h-1)) end
   end
   if t=="temple" then st(r.x+r.w\2,r.y+r.h\2,7) end
   if t=="fountain" then st(r.x+r.w\2,r.y+r.h\2,8) end
   if t=="trap" then for n=1,rr(3,6) do add_trap() end end
  end
 end
 local a=rooms[1] upx=a.x+a.w\2 upy=a.y+a.h\2 st(upx,upy,5)
 local b=rooms[#rooms] downx=b.x+b.w\2 downy=b.y+b.h\2 st(downx,downy,6)
 if d==1 then local r=rooms[min(2,#rooms)] st(r.x+r.w\2,r.y+r.h\2,7) end
 if dir and dir<0 then pl.x=downx pl.y=downy else pl.x=upx pl.y=upy end
 if d==12 and not pl.hasamu then place_item("amulet",downx,downy) end
 for i=1,4+d\2 do place_item(loot_kind()) end
 for i=1,5+d*2 do add_mon() end
 if pl.hasamu then for i=1,2+d\2 do add_mon() end msg("the dungeon wakes",8) end
 for i=1,3+d\2 do add_trap() end
 upd_vis()
 msg("welcome to level "..d,11)
end

-- add a random trap at a free position
function add_trap()
 for z=1,400 do
  local x,y=freepos()
  if not traps[ix(x,y)] and not bydoor(x,y) then
   traps[ix(x,y)]={x=x,y=y,t=one({"pit","arrow","sleep","teleport","poly","rust"}),seen=false}
   return
  end
 end
end

-- add a monster, optionally at a specific position
function add_mon(x,y,awake)
 if not x then x,y=freepos() end
 local maxm=mid(1,depth+3,#mtdefs)
 local d=mtdefs[rr(1,maxm)]
 add(mons,{n=d.n,ch=d.ch,c=d.c,x=x,y=y,h=d.h+depth,a=d.a+depth\2,xp=d.xp,s=d.s,awake=awake or rnd()<depth/28})
end

-- start a new run from the selected role
function make_player()
 local r=roles[rp]
 levels={} knp={} kns={} knw={} msgs={}
 local wi={k="weapon",n=r.w,d=weps[r.w].d,bu=0}
 local ai={k="armor",n=r.a,ac=arms[r.a],r=0,bu=0}
 pl={x=1,y=1,role=r.n,maxhp=r.hp,hp=r.hp,str=r.str,dex=r.dex,
     ac=r.ac,baseac=r.ac+ai.ac,xp=0,lev=1,g=r.g,hunger=r.food,inv={},w=wi,a=ai,
     prayer=0,stun=0,conf=0,hallu=0,fast=0,poly=0,hasamu=false}
 add(pl.inv,wi)
 add(pl.inv,ai)
 calc_ac()
 add(pl.inv,new_item("food"))
 if r.wand==1 then add(pl.inv,new_item("wand")) end
 if r.pot>0 then for i=1,r.pot do add(pl.inv,new_item("potion")) end end
 turn=0 gen_level(1,1) mode="play"
 msg("you are a "..r.n,10)
 bgm(1)
end

-- return the monster occupying a cell, if any
function mon_at(x,y)
 for m in all(mons) do if m.x==x and m.y==y then return m end end
end

-- return all items stacked on a cell
function item_at(x,y)
 local t={}
 for it in all(items) do if it.x==x and it.y==y then add(t,it) end end
 return t
end

-- bresenham-style line of sight between two cells
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

-- update visible and remembered tiles around player
function upd_vis()
 for i=0,mw*mh-1 do vis[i]=0 end
 for y=pl.y-8,pl.y+8 do
  for x=pl.x-12,pl.x+12 do
   if inb(x,y) and dist(pl.x,pl.y,x,y)<=12 and los(pl.x,pl.y,x,y) then
    local k=ix(x,y) vis[k]=1 seen[k]=1
    local tr=traps[k] if tr and rnd()<.04+pl.dex/110 then tr.seen=true end
   end
  end
 end
 for m in all(mons) do if vis[ix(m.x,m.y)]==1 then m.awake=true end end
end

-- dispatch update logic by screen mode
function _update()
 if mode=="title" then up_title()
 elseif mode=="play" then up_play()
 elseif mode=="inv" then up_inv()
 elseif mode=="aim" then up_aim()
 elseif mode=="dead" or mode=="win" then if btnp(4) or btnp(5) then mode="title" bgm(0) end
 end
end

-- handle role selection and title actions
function up_title()
 if btnp(0) then rp=max(1,rp-1) end
 if btnp(1) then rp=min(#roles,rp+1) end
 if btnp(4) or btnp(5) then make_player() end
end

-- handle movement, action, and inventory in play
function up_play()
 local dx,dy=dir_input()
 if dx~=0 or dy~=0 then try_move(dx,dy) return end
 if btnp(4) then act() return end
 if btnp(5) then sel=1 mode="inv" end
end

-- read cardinal or diagonal d-pad input
function dir_input()
 if btnp(0) or btnp(1) or btnp(2) or btnp(3) then
  local dx=0 local dy=0
  if btn(0) then dx-=1 end
  if btn(1) then dx+=1 end
  if btn(2) then dy-=1 end
  if btn(3) then dy+=1 end
  return dx,dy
 end
 return 0,0
end

-- spend one turn and advance world state
function spend()
 turn+=1
 for s in all({"stun","conf","hallu","fast"}) do if pl[s]>0 then pl[s]-=1 end end
 if pl.poly>0 then
  pl.poly-=1
  if pl.poly<1 then
   pl.str=pl.ostr pl.dex=pl.odex pl.ostr=nil
   msg("you feel like yourself",13)
  end
 end
 pl.hunger-=1
 if pl.hunger<80 and turn%8==0 then hurt(rr(1,3),"starvation") end
 if mode=="dead" then return end
 if turn%45==0 and #mons<8+depth*3 and rnd()<.4 then
  local x,y=freepos(true) add_mon(x,y,true) msg("you hear movement",5)
 end
 if pl.fast<1 or turn%2==1 then move_mons() end
 upd_vis()
 if pl.hp<pl.maxhp and turn%30==0 and pl.hunger>250 then pl.hp+=1 end
 if pl.lev<12 and pl.xp>=pl.lev*pl.lev*16 then pl.lev+=1 pl.maxhp+=rr(3,6) pl.hp=pl.maxhp pl.str+=1 msg("you feel more experienced",11) end
end

-- attempt player movement or bump attack
function try_move(dx,dy)
 if (pl.stun>0 and rnd()<.35) or (pl.conf>0 and rnd()<.5) then dx=rr(-1,1) dy=rr(-1,1) end
 if not clear_diag(pl.x,pl.y,pl.x+dx,pl.y+dy) then return end
 local x=pl.x+dx local y=pl.y+dy
 local m=mon_at(x,y)
 if m then attack(m) spend() return end
 if gt(x,y)==3 and dx*dy==0 then st(x,y,4) msg("the door opens") spend() return end
 if pass(x,y) then
  pl.x=x pl.y=y
  local tr=traps[ix(x,y)]
  if tr then trigger_trap(tr) end
  spend()
 end
end

-- context action for pickup, stairs, features, search
function act()
 local v=gt(pl.x,pl.y)
 local its=item_at(pl.x,pl.y)
 if #its>0 then pickup(its) spend() return end
 if v==6 then load_level(depth+1,1) spend() return end
 if v==5 then
  if depth==1 then
   msg(pl.hasamu and "offer yendor at altar" or "the way out is sealed",10)
   return
  end
  load_level(max(1,depth-1),-1) spend() return
 end
 if v==7 then altar() if mode=="play" then spend() end return end
 if v==8 then drink_fountain() spend() return end
 search() spend()
end

-- pick up all items on the current tile
function pickup(its)
 for it in all(its) do
  local k=it.k
  if k=="gold" then pl.g+=it.q msg("picked up "..it.q.." gold",10) del(items,it)
  elseif k=="amulet" then pl.hasamu=true msg("you have yendor!",10) msg("the dungeon wakes",8) bgm(2) del(items,it)
  elseif it.unp and pl.g<it.p then msg("you need "..it.p.." gold",8) return
  elseif #pl.inv<10 then
   if it.unp then pl.g-=it.p msg("paid "..it.p.." gold",10) it.unp=nil end
   add(pl.inv,it) msg("picked up "..iname(it),7) del(items,it)
  else msg("pack is full",8) end
 end
end

-- search adjacent tiles for hidden traps
function search()
 local found=false
 for yy=-1,1 do for xx=-1,1 do
  local tr=traps[ix(pl.x+xx,pl.y+yy)]
  if tr and not tr.seen and rnd()<.25+pl.dex/45 then tr.seen=true found=true end
 end end
 if found then msg("you find a trap",10) else msg("you search",5) end
end

-- apply trap effect when stepped on
function trigger_trap(tr)
 tr.seen=true
 if tr.t=="pit" then msg("you fall into a pit!",8) hurt(rr(2,7)+depth\3,"pit") end
 if tr.t=="arrow" then msg("an arrow shoots out!",8) hurt(rr(1,6)+depth\4,"arrow trap") end
 if tr.t=="sleep" then msg("sleep gas!",13) pl.stun=rr(3,7)+depth\4 end
 if tr.t=="teleport" then msg("you teleport",13) pl.x,pl.y=freepos() end
 if tr.t=="poly" then msg("you feel different",14) poly_self(-1) end
 if tr.t=="rust" then
  if pl.a then pl.a.r+=1 calc_ac() msg("your armor rusts",4)
  else msg("rust flakes away",5) end
 end
end

function poly_self(b)
 if b<0 and rnd()<.35 then hurt(rr(4,12)+depth,"system shock") if mode=="dead" then return end end
 local d=one(mtdefs)
 if not pl.ostr then pl.ostr=pl.str pl.odex=pl.dex end
 pl.poly=rr(24,48)
 pl.str=mid(3,d.a+depth\2,16) pl.dex=mid(3,d.h,16)
 msg("you become "..d.n,14)
end

-- resolve player melee attack against a monster
function attack(m)
 local hit=rr(1,20)+pl.dex+pl.lev
 if hit>9+depth+depth\4 then
  local wd=pl.w and pl.w.d or 3
  local dm=rr(1,wd)+pl.str\3
  if m.s==3 and rnd()<.3 then pl.stun=rr(2,5) msg("the eye freezes you",12) end
  m.h-=dm msg("you hit "..m.n.." "..dm,7)
  if m.h<=0 then
   msg("you kill "..m.n,11) pl.xp+=m.xp corpse(m) del(mons,m)
  end
 else msg("you miss "..m.n,5) end
end

function corpse(m)
 if rnd()<.15 or m.s>2 then add(items,{k="food",n=m.n.." corpse",q=rr(50,160),x=m.x,y=m.y,s=m.s,bu=0}) end
end

-- move monsters and perform monster attacks
function move_mons()
 pathmap()
 for m in all(mons) do
  if m.h>0 then
   local dx=0 local dy=0
   if m.flee and m.flee>0 then
    m.flee-=1 dx=sgn(m.x-pl.x) dy=sgn(m.y-pl.y)
   elseif adj(m.x,m.y,pl.x,pl.y) and clear_diag(m.x,m.y,pl.x,pl.y) then mon_hit(m)
   else
    if m.awake or dist(m.x,m.y,pl.x,pl.y)<7 then
     local bx=m.x local by=m.y local bd=pd[ix(m.x,m.y)] or 99
     local d=pd[ix(m.x+1,m.y)] if d and d<bd and not mon_at(m.x+1,m.y) then bx=m.x+1 by=m.y bd=d end
     d=pd[ix(m.x-1,m.y)] if d and d<bd and not mon_at(m.x-1,m.y) then bx=m.x-1 by=m.y bd=d end
     d=pd[ix(m.x,m.y+1)] if d and d<bd and not mon_at(m.x,m.y+1) then bx=m.x by=m.y+1 bd=d end
     d=pd[ix(m.x,m.y-1)] if d and d<bd and not mon_at(m.x,m.y-1) then bx=m.x by=m.y-1 end
     dx=bx-m.x dy=by-m.y
    elseif rnd()<.25 then dx=rr(-1,1) dy=rr(-1,1) end
   end
   local nx=m.x+dx local ny=m.y+dy
   if pass(nx,ny) and not mon_at(nx,ny) and not (pl.x==nx and pl.y==ny) then m.x=nx m.y=ny end
  end
 end
end

-- resolve a monster melee attack against the player
function mon_hit(m)
 local hit=rr(1,20)+m.a+depth\5
 local ap=10-pl.ac
 if hit>10+ap+pl.dex\3 then
  local dm=max(1,rr(1,m.a+2+depth\4)-ap\2)
  if m.s==2 and #pl.inv>0 and rnd()<.18 then
   local it=pl.inv[#pl.inv] deli(pl.inv,#pl.inv)
   if it==pl.w then pl.w=nil end
   if it==pl.a then pl.a=nil calc_ac() end
   m.x,m.y=freepos(true)
   msg(m.n.." steals "..iname(it),14) return
  end
  if m.s==4 and rnd()<.25 then pl.lev=max(1,pl.lev-1) msg("life drains away",13) end
  hurt(dm,m.n)
 else
  if vis[ix(m.x,m.y)]==1 then msg(m.n.." misses",5) end
 end
end

-- damage the player and die if hp reaches zero
function hurt(n,why)
 pl.hp-=n
 if pl.hp<=0 then death(why) else msg("ouch "..n.." hp",8) end
end

-- enter death state and save score
function death(why)
 mode="dead" cause=why
 bgm(-1)
end

function altar()
 if depth==1 and pl.hasamu then mode="win" bgm(3) return end
 local n=0
 for it in all(pl.inv) do if not it.bk then it.bk=true n+=1 end end
 if n>0 then msg("the altar reveals "..n,10) return end
 pray()
end

-- altar prayer with cooldown and need-based reward
function pray()
 if turn<pl.prayer then msg("the gods are silent",5) return end
 pl.prayer=turn+320
 for it in all(pl.inv) do
  if it.bu<0 and (it==pl.w or it==pl.a) then it.bu=0 it.bk=true msg("a curse lifts",11) return end
 end
 if pl.hunger<250 then pl.hunger+=500 msg("manna fills you",11)
 elseif pl.hp<pl.maxhp then pl.hp=pl.maxhp msg("you are healed",11)
 else msg("you feel watched",11) end
end

-- random fountain outcome
function drink_fountain()
 local r=rr(1,5)
 if r==1 then pl.hp=min(pl.maxhp,pl.hp+rr(4,10)) msg("cool water heals",12)
 elseif r==2 then water_demon()
 elseif r==3 then place_item("gem",pl.x,pl.y) msg("something glitters",10)
 elseif r==4 then pl.stun=rr(3,6) msg("the water was odd",13)
 else msg("the fountain dries up",5) st(pl.x,pl.y,1) end
end

function water_demon()
 local x,y
 for z=1,20 do
  local dx=rr(-1,1) local dy=rr(-1,1)
  x=pl.x+dx y=pl.y+dy
  if (dx~=0 or dy~=0) and pass(x,y) and not mon_at(x,y) then break end
  x=nil
 end
 if not x then x,y=freepos() end
 add(mons,{n="water demon",ch="&",c=12,x=x,y=y,h=18+depth,a=7+depth\2,xp=32,s=1,awake=true})
 msg("you unleash a water demon",8)
end

-- handle inventory menu navigation and actions
function up_inv()
 if btnp(5) then mode="play" return end
 local n=#pl.inv+1
 if btnp(2) then sel-=1 if sel<1 then sel=n end end
 if btnp(3) then sel+=1 if sel>n then sel=1 end end
 if (btnp(0) or btnp(1)) and sel<=#pl.inv then
  drop_item(sel)
  sel=min(sel,#pl.inv+3)
  mode="play" spend()
  return
 end
 if btnp(4) then
  if sel<=#pl.inv then use_item(pl.inv[sel],sel) if mode~="inv" then return end
  else pray() end
  mode="play" spend()
 end
end

-- drop an inventory item onto the current tile
function drop_item(i)
 local it=pl.inv[i]
 if not it then return end
 if (it==pl.w or it==pl.a) and it.bu<0 then it.bk=true msg("it is cursed",8) return end
 deli(pl.inv,i)
 if it==pl.w then pl.w=nil end
 if it==pl.a then pl.a=nil calc_ac() end
 if gt(pl.x,pl.y)==9 and not it.unp and it.k~="amulet" then
  local p=price(it)\2 pl.g+=p msg("sold "..iname(it),10) return
 end
 it.x=pl.x it.y=pl.y
 add(items,it)
 msg("dropped "..iname(it),5)
end

-- use or equip an inventory item
function use_item(it,i)
 local k=it.k
 if k=="weapon" then pl.w=it msg("wielding "..iname(it),10) return end
 if k=="armor" then pl.a=it calc_ac() msg("wearing "..iname(it),10) return end
 if k=="food" then eat(it) deli(pl.inv,i) return end
 if k=="potion" then quaff(it) deli(pl.inv,i) return end
 if k=="scroll" then deli(pl.inv,i) read_scroll(it) return end
 if k=="wand" then aim_it=it mode="aim" msg("aim wand",13) return end
 if k=="gem" then pl.g+=50 msg("you appraise the gem",10) deli(pl.inv,i) return end
 msg("nothing happens",5)
end

function eat(it)
 pl.hunger+=it.q msg("you eat "..iname(it),11)
 if it.s==4 then pl.xp+=24 msg("cold power rises",13)
 elseif it.s==3 then
  for i=0,mw*mh-1 do local tr=traps[i] if tr and dist(pl.x,pl.y,tr.x,tr.y)<8 then tr.seen=true end end
  msg("strange sight opens",12)
 elseif it.s and it.s>0 and rnd()<.25 then hurt(rr(1,6),"bad corpse") end
end

-- apply potion effect and identify its type
function quaff(it)
 knp[it.id]=true it.bk=true
 local b=it.bu local n=it.id
 if n==1 then
  pl.hp=min(pl.maxhp,pl.hp+(b<0 and rr(2,6) or rr(8,18)+(b>0 and 10 or 0)))
  if b>0 then pl.stun=0 pl.conf=0 end
  msg("you feel better",11)
 elseif n==2 then pl.fast=max(pl.fast,rr(8,20)+(b>0 and 20 or 0)) msg("you feel quick",11)
 elseif n==3 then
  if b<0 then msg("it tastes foul",8)
  elseif b>0 then pl.str+=1 pl.dex+=1 msg("you feel able",11)
  elseif rnd()<.5 then pl.str+=1 msg("you feel strong",11)
  else pl.dex+=1 msg("you feel agile",11) end
 elseif n==4 then
  if pl.role=="healer" then msg("you are immunized",11)
  else hurt(rr(1,4)+(b<1 and rr(2,6) or 0),"sickness") end
 elseif n==5 then pl.conf=max(pl.conf,rr(8,18)+(b<0 and 16 or 0)) msg("you reel",13)
 elseif n==6 then pl.hallu=max(pl.hallu,rr(14,30)+(b<0 and 20 or 0)) msg("colors swirl",13)
 else poly_self(b) end
end

-- apply scroll effect and identify its type
function read_scroll(it)
 kns[it.id]=true it.bk=true
 local b=it.bu local n=it.id local cf=pl.conf>0 local bad=b<0 or cf
 if n==1 then
  msg("this is identify",11)
  if bad then return end
  for it in all(pl.inv) do if not known(it) then known(it,true) msg("identified "..iname(it),11) return end end
  msg("nothing else to identify",5)
 elseif n==2 then
  if bad then
   local d=rr(1,12)
   if d==depth then pl.x,pl.y=freepos() else load_level(d,d>depth and 1 or -1) end
   msg("level teleport",13)
  else pl.x,pl.y=freepos(b>0) msg("you teleport",13) end
 elseif n==3 then
  if pl.w then pl.w.bk=true
   if bad then pl.w.bu=-1 pl.w.d=max(1,pl.w.d-1) msg("your weapon blackens",8)
   else pl.w.bu=max(0,pl.w.bu) pl.w.d=min(11,pl.w.d+(b>0 and 2 or 1)) msg("your weapon glows",10) end
  end
 elseif n==4 then
  for i=0,mw*mh-1 do if not bad or rnd()<.35 then seen[i]=1 end local tr=traps[i] if b>0 and tr then tr.seen=true end end
  msg(bad and "the map twists" or "the level is revealed",bad and 13 or 10)
 elseif n==5 then
  for m in all(mons) do if dist(m.x,m.y,pl.x,pl.y)<(b>0 and 9 or 6) then m.awake=true m.flee=bad and 0 or (b>0 and 18 or 10) end end
  msg(bad and "monsters are stirred" or "monsters flee",bad and 8 or 12)
 else
  if b<0 then msg("nothing happens",5) return end
  local c=0
  if cf then
   for it in all(pl.inv) do if b>0 or it==pl.w or it==pl.a then it.bu=rr(0,1)*2-1 it.bk=false c+=1 end end
  else
   for it in all(pl.inv) do if (b>0 or it==pl.w or it==pl.a) and it.bu<0 then it.bu=0 it.bk=true c+=1 end end
  end
  msg(c>0 and (cf and "magic shifts" or c.." curses lift") or "nothing happens",c>0 and 11 or 5)
 end
end

function wand_ok(it)
 if it.z<0 or it.z==0 and rnd(121)>=1 then msg("nothing happens",5) return end
 if it.z==0 then msg("one last charge",10) end
 it.z-=1
 if it.bu<0 and rnd(100)<1 then msg("the wand explodes",8) hurt(rr(2,12),"exploding wand") del(pl.inv,it) return end
 return true
end

-- handle one-step wand direction selection
function up_aim()
 if btnp(5) then mode="play" msg("never mind",5) return end
 local dx,dy=dir_input()
 if dx~=0 or dy~=0 then
  if wand_ok(aim_it) then zap(aim_it,dx,dy) end
  if mode~="dead" then mode="play" spend() end
 end
end

-- trace wand ray and apply wall or monster hit
function zap(it,dx,dy)
 knw[it.id]=true
 local x=pl.x local y=pl.y
 for i=1,12 do
  x+=dx y+=dy
  if not inb(x,y) then break end
  if it.id==3 then
   if block(x,y) then st(x,y,4) seen[ix(x,y)]=1 msg("rock turns to dust",13) return end
  else
   local m=mon_at(x,y)
   if m then wand_hit(it,m) return end
   if block(x,y) then break end
  end
 end
 msg("the wand buzzes",5)
end

-- apply non-digging wand effects to a monster
function wand_hit(it,m)
 if it.id==1 then m.h-=rr(8,18) msg("missile strikes "..m.n,10)
 elseif it.id==2 then m.h-=rr(12,24) msg("fire burns "..m.n,9)
 elseif it.id==5 then m.x,m.y=freepos(true) m.awake=true msg(m.n.." vanishes",13) return
 else local d=one(mtdefs) m.n=d.n m.ch=d.ch m.c=d.c m.h=d.h+depth m.a=d.a+depth\2 m.xp=d.xp m.s=d.s msg("it changes shape",14) end
 if m.h<=0 then msg(m.n.." dies",11) pl.xp+=m.xp corpse(m) del(mons,m) end
end

-- dispatch drawing by screen mode
function _draw()
 cls(0)
 if mode=="title" then draw_title()
 elseif mode=="play" or mode=="aim" then draw_game()
 elseif mode=="inv" then draw_game() draw_inv()
 elseif mode=="dead" then draw_end(false)
 elseif mode=="win" then draw_end(true) end
end

-- draw title and role selection screen
function draw_title()
 print("netacht",50,10,10)
 print("a pico-8 nethack demake",20,18,6)
 local r=roles[rp]
 rect(16,36,112,84,5)
 print("< "..r.n.." >",36,42,11)
 print("hp "..r.hp.." str "..r.str.." dex "..r.dex,26,52,7)
 print("o start",48,104,7)
end

-- draw dungeon viewport, hud, actors, and messages
function draw_game()
 rectfill(0,0,127,11,1)
 print("dl"..depth.." lv"..pl.lev.." hp"..pl.hp.."/"..pl.maxhp.." ac"..pl.ac.." $"..pl.g,1,1,7)
 local hs="satiated" if pl.hunger<500 then hs="hungry" end if pl.hunger<250 then hs="weak" end if pl.hunger<100 then hs="faint" end
 print(pl.role.." "..hs.." "..(pl.w and pl.w.n or "hands"),1,7,6)
 local vw=32 local vh=16
 local cw=4 local chh=6
 local cx=mid(0,pl.x-vw\2,mw-vw) local cy=mid(0,pl.y-vh\2,mh-vh)
 for sy=0,vh-1 do
  for sx=0,vw-1 do
   local x=cx+sx local y=cy+sy local k=ix(x,y)
   if seen[k]==1 then
    local v=gt(x,y) local lit=vis[k]==1 local ch=tc[v+1] or "." local co=lit and (tco[v+1] or 6) or 5 local over=false
    local tr=traps[k]
    if tr and tr.seen and lit then ch="^" co=8 over=true end
    if lit then
     local its=item_at(x,y)
     if #its>0 then local it=its[#its] ch=oc[it.k] or "*" co=oco[it.k] or 9 over=true end
     local m=mon_at(x,y)
     if m then
      if pl.hallu>0 then local h="?&@#$%!" local p=rr(1,#h) ch=sub(h,p,p) co=rr(8,14)
      else ch=m.ch co=m.c end
      over=true
     end
    end
    if v==2 and not over then
     rectfill(sx*cw,13+sy*chh,sx*cw+cw-1,12+(sy+1)*chh,co)
    else
     print(ch,sx*cw,13+sy*chh,co)
    end
   end
  end
 end
 print("@",(pl.x-cx)*cw,13+(pl.y-cy)*chh,15)
 rectfill(0,109,127,127,0)
 for i=1,#msgs do print(msgs[i].s,1,103+i*6,msgs[i].c) end
end

-- draw inventory overlay
function draw_inv()
 rectfill(0,18,127,127,0)
 rect(10,18,118,121,7)
 print("pack",48,23,10)
 local y=31 local n=#pl.inv
 for i=1,n do
  local it=pl.inv[i]
  local eq=it==pl.w or it==pl.a
  local s=(i==sel and ">" or " ")..(eq and "*" or " ")..iname(it)..(it.d and " d"..it.d or it.ac and " ac"..it.ac or it.z and "["..it.z.."]" or "")
  local co=i==sel and (eq and 14 or 11) or (eq and 10 or 6)
  print(sub(s,1,25),16,y,co) y+=6
 end
 local ms={"pray"}
 for j=1,1 do
  local i=n+j
  print((sel==i and ">" or " ")..ms[j],16,y,sel==i and 11 or 6) y+=6
 end
 print("o use  <> drop  x close",16,115,5)
end

-- draw death or ascension screen
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

__label__
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
17711711177111111711171717711111171717771771177711171771171711111777117717711111177717111777111111111111111111111111111111111111
17171711117111111711171711711111171717171171171711711171171711111717171111711111177117111717111111111111111111111111111111111111
17171711117111111711171711711111177717771171171711711171177711111777171111711111117717771717111111111111111111111111111111111111
17171711117111111711177711711111171717111171171711711171111711111717171111711111177717171717111111111111111111111111111111111111
17771777177711111777117117771111171717111777177717111777111711111717117717771111117117771777111111111111111111111111111111111111
11111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111111
16661166116616161666111111661666166616661666166616661661111116611666116611661666166611111111111111111111111111111111111111111111
16161616161116161611111116111616116111611616116116111616111116161616161116111611161611111111111111111111111111111111111111111111
16611616161116161661111116661666116111611666116116611616111116161666161116111661166111111111111111111111111111111111111111111111
16161616161616161611111111161616116111611616116116111616111116161616161616161611161611111111111111111111111111111111111111111111
16161661166611661666111116611616116116661616116116661666111116661616166616661666161611111111111111111111111111111111111111111111
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000055555555555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000055555555555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000055555555555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000055555555555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000055555555555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000055555555555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000005000500050000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000050005000500050000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000005000500000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000005000500000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000055555555555555555555555555550dd0555555555555555555555555555555555555000000000000000000000000
00000000000000000000000000000000000055555555555555555555555555550dd0555555555555555555555555555555555555000000000000000000000000
00000000000000000000000000000000000055555555555555555555555555550dd0555555555555555555555555555555555555000000000000000000000000
00000000000000000000000000000000000055555555555555555555555555550dd0555555555555555555555555555555555555000000000000000000000000
00000000000000000000000000000000000055555555555555555555555555550dd0555555555555555555555555555555555555000000000000000000000000
00000000000000000000000000000000000055555555555555555555555555550dd0555555555555555555555555555555555555000000000000000000000000
0000000000000000000000000dd00dd0000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000dd00dd0000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
000000000000000000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd000000000000000000000
000000000000000000000000ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd000000000000000000000
0000000000000000000000000dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd000000000000000000000
0000000000000000000000000dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd000000000000000000000
000000000000000000000000000000000000000000000dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd000000000000000000000
000000000000000000000000000000000000000000000dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd00dd000000000000000000000
00000000000000000000000000000000000000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd0000000000000000
00000000000000000000000000000000000000000000dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd0000000000000000
000000000000000000000000000000000000000000000000000000000dd00dd00dd00dd00dd00dd00dd00dd00dd00000000000000dd000000000000000000000
000000000000000000000000000000000000000000000000000000000dd00dd00dd00dd00dd00dd00dd00dd00dd00000000000000dd000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000fd0000000000000000000000000555500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000fdf0000000000000000000000000555500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000fdfd000000000000000000000000555500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000fddd000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555050005000ff0050005000500050005000500555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000000000000000000555500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000dddd000000000000000000000000555500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000dddd000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555050005000dd0050005000500050005000500555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000700dd00dd000000000000000000000055000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000007000dd00dd009000900000000000000055000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000dddd00007000dddddddd99909990dddddddddddd555555555555555555550000
0000000000000000000000000000000000000000000000000000555500000000dddd00000700dddddddd09000900dddddddddddd555555555555555555550000
00000000000000000000000000000000000000000000000000005555050005000dd0050000700dd00dd000000000000000000000055000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000dd00dd000000000000000000000055000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000000000000000000555500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000dddd000000000000000000000000555500000000000000000000000000000000
0000000000000000000000000000000000000000000000000000555500000000dddd000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555050005000dd0050005000500050005000500555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555000000000dd0000000000000000000000000555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555555555550dd0555555555555555555555555555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555555555550dd0555555555555555555555555555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555555555550dd0555555555555555555555555555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555555555550dd0555555555555555555555555555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555555555550dd0555555555555555555555555555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000005555555555550dd0555555555555555555555555555500000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000005555dddd000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000005555dddd000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555555550dd0555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555555550dd0555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555555550dd0555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555555550dd0555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555555550dd0555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000555555550dd0555500000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000dd0000000000000000000000000000000000000000000000000000000000000
05050055055500550500055000000555055500550055055500550000000000000000000000000000000000000000000000000000000000000000000000000000
05050505050505050500050500000555005005000500050005000000000000000000000000000000000000000000000000000000000000000000000000000000
05500505055005050500050500000505005005550555055005550000000000000000000000000000000000000000000000000000000000000000000000000000
05050505050505050500050500000505005000050005050000050000000000000000000000000000000000000000000000000000000000000000000000000000
05050550055505500555055500000505055505500550055505500000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
07070077070700000707077707770000070700770777007707000770000007000000000000000000000000000000000000000000000000000000000000000000
07070707070700000707007000700000070707070707070707000707000007000000000000000000000000000000000000000000000000000000000000000000
07770707070700000777007000700000077007070770070707000707000007770000000000000000000000000000000000000000000000000000000000000000
00070707070700000707007000700000070707070707070707000707000007070000000000000000000000000000000000000000000000000000000000000000
07770770007700000707077700700000070707700777077007770777000007770000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0b0b00bb0b0b00000b0b0bbb0b000b0000000b0b00bb0bbb00bb0b000bb000000000000000000000000000000000000000000000000000000000000000000000
0b0b0b0b0b0b00000b0b00b00b000b0000000b0b0b0b0b0b0b0b0b000b0b00000000000000000000000000000000000000000000000000000000000000000000
0bbb0b0b0b0b00000bb000b00b000b0000000bb00b0b0bb00b0b0b000b0b00000000000000000000000000000000000000000000000000000000000000000000
000b0b0b0b0b00000b0b00b00b000b0000000b0b0b0b0b0b0b0b0b000b0b00000000000000000000000000000000000000000000000000000000000000000000
0bbb0bb000bb00000b0b0bbb0bbb0bbb00000b0b0bb00bbb0bb00bbb0bbb00000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
011800000c0300c0200c0200c0100000000000000000000007030070200702007010000000000000000000000f0300f0200f0200f010000000000000000000000a0300a0200a0200a01000000000000000000000
011800002473500000000000000000000000001f73500000000000000000000000002773500000000000000000000000002473500000000000000000000000001b7350000000000000001f735000000000000000
01180000181200000000000000001b1200000000000000001f1200000000000000002212000000000000000024120000000000000000221200000000000000001f1200000000000000001b120000000000000000
011000000c2300c22000000000000c2300c2200000000000082300822000000000000b2300b22000000000000c2300c22000000000000f2300f22000000000000b2300b220000000000008230082200000000000
01100000277330000000000000001e7330000000000000002a73300000000000000021733000000000000000277330000000000000001e7330000000000000002b73300000000000000024733000000000000000
011800000c0300000013020000000000000000000000000013030000001a020000000000000000000000000018030000001f02000000000000000000000000001f03000000260200000000000000000000000000
011800001873500000000001f73500000000002473500000000002773500000000002b735000000000000000307350000000000000002b7350000000000000002773500000000000000024735000000000000000
__music__
03 40410001
03 40410002
03 40410304
03 40410506
