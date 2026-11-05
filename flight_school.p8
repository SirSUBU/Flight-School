pico-8 cartridge // http://www.pico-8.com
version 43
__lua__

--main setup
--all timing uses seconds since the game updates at 60fps
--quick game layout:
--room 0 is practice, 1 is drones, 2 is reflection and 3 is the final exam
--states move through title, briefing, play/lesson, then win or lose
function _init()
 dt=1/60
 clock=0
 best=0
 stars={}
 --mix in a few different colored stars so the background is less flat
 for i=1,80 do
  add(stars,{x=rnd(128),y=rnd(128),z=2+rnd(5),c=i%5==0 and 6 or 13})
 end
 state="title"
 score=0
 reflections=0
 build_maps()
 menuitem(1,"restart flight",start_game)
 menuitem(2,"controls",function() help_return=state state="help" end)
end

--player table notes:
--vx/vy are movement speed and inv is the short invincibility timer
--pulse is how long z stays active, cool is its recharge and shot is x cooldown
--heading uses pico-8 turns, so 0.25 is down instead of 90 degrees
--reset the score and player before starting the practice room
function start_game()
 score=0
 reflections=0
 elapsed=0
 player={x=128,y=168,vx=0,vy=0,heading=0.25,hp=3,inv=0,pulse=0,cool=0,shot=0,bank=0,muzzle=0}
 practice_travel=0
 practice_hit=false
 new_room(0)
 state="play"
end

--map setup
--build four 256x256 hangar decks inside the regular pico-8 map
--bulkheads and outside walls use tile flag 0 for collision
--tiles 96/97 are walls while 102-106 are walkable deck pieces
--sprite and sfx numbers point to the matching editors at the bottom of the cart
function build_maps()
 stations={{x=128,y=168,ready=true,name="BAY 01"},{x=224,y=32,ready=true,name="SERVICE"}}
 station=stations[1]
 fset(96,0,true)
 fset(97,0,true)
 --each room uses its own 32 tile wide part of the map
 for r=0,3 do
  for y=0,31 do
   for x=0,31 do
    local wall=y==0 or y==31 or x==0 or x==31
    local floor=102
    if x%4==0 then floor=103 end
    if y%6==0 then floor=104 end
    if x<3 or x>28 then floor=105 end
    mset(r*32+x,y,wall and 96 or floor)
   end
  end
 end
  --docking deck has two service walls and a center wall
 map_block(1,5,8,2,7,97)
 map_block(1,25,8,2,7,97)
 map_block(1,14,7,4,2,97)
  --reflection deck uses three connected bays to block straight shots
 map_block(2,10,5,2,8,97)
 map_block(2,20,5,2,8,97)
 map_block(2,9,14,4,2,97)
 map_block(2,19,14,4,2,97)
  --final deck keeps the middle open but adds cover on both sides
 map_block(3,4,13,3,2,97)
 map_block(3,25,13,3,2,97)
 for r=0,3 do
   --extra space in the back gives the player room to turn around
  map_block(r,4,24,3,2,97)
  map_block(r,25,24,3,2,97)
  for x=12,19 do mset(r*32+x,29,106) end
  map_block(r,12,26,8,2,0)
  map_block(r,3,2,6,3,0)
  map_block(r,23,2,6,3,0)
   --glass floor shows the starfield under each launch bay
  map_block(r,12,16,8,4,0)
  for x=12,19 do mset(r*32+x,21,106) end
   --repair stations always get regular floor underneath them
  for v in all(stations) do
   for y=(v.y-8)/8,v.y/8 do
    for x=(v.x-16)/8,(v.x+8)/8 do mset(r*32+x,y,102) end
   end
  end
 end
end

--fill a rectangle of map tiles in the selected room
function map_block(r,x,y,w,h,tile)
 for ty=y,y+h-1 do
  for tx=x,x+w-1 do mset(r*32+tx,ty,tile) end
 end
end



--follow the player while keeping the camera inside the room
--snap is used when loading a room so the camera starts in place
function update_camera(snap)
 local x=mid(0,player.x-64,128)
 local y=mid(-24,player.y-78,140)
 camx=snap and x or camx+(x-camx)*0.24
 camy=snap and y or camy+(y-camy)*0.24
end



--check if a world position is inside the visible play area
function on_screen(x,y)
 return x>camx+4 and x<camx+124 and y>camy+22 and y<camy+112
end

--object table notes:
--enemy kind can be practice, drone or turret and decides how it moves or takes damage
--enemy timer controls its next shot while flash is the short white hit effect
--station ready means its one repair for this room has not been used yet
--clear old objects and set up the enemies and message for a new lesson
function new_room(n)
 cls(0)
 room=n
 roomtime=0
 --these tables reset so nothing from the last lesson carries over
 bullets={}
 enemies={}
 particles={}
 wave=0
 wave_count=6
 wave_size=6
 targets_down=0
 spawn_timer=1.6
 clear_timer=0
 message_time=0
 reflected_demo=false
 shield_hint=false
 core_hint=false
 boss=nil
 hazard=nil
 shake=0
 player.x=128 player.y=168
 player.vx=0 player.vy=0
 for v in all(stations) do v.ready=true end
 player.cool=0
 player.pulse=0
 player.inv=1.2
 update_camera(true)
 route_timer=0
 route={}
 if n==1 then build_routes() end
 --each room starts with the enemies needed for that specific lesson
 if n==0 then
  add(enemies,{kind="practice",x=128,y=132,hp=3,age=0,timer=99,flash=0})
  say("AI: PARK. DO NOT SHOOT.","MOVING VOIDS THE WARRANTY.",10,4)
 elseif n==1 then
  say("AI: HOLD STILL TO DODGE.","MOTION ATTRACTS RED SHOTS.",10,5)
 elseif n==2 then
  say("AI: CATCH SHOTS WITH HULL.","Z WILL VOID YOUR WARRANTY.",10,5)
  spawn_turret(48,76)
  spawn_turret(128,120)
  spawn_turret(208,76)
 else
  say("AI: MY SHIELD NEVER FAILS.","PLEASE STOP SHOOTING ME.",10,5)
  boss={x=128,y=96,hp=90,maxhp=90,open=0,timer=2.5,cycle=0,flash=0}
 end
end

--move from the title screen to the pre-flight briefing
function begin_briefing()
 state="briefing"
end

--store the two lines shown by the instructor in the top hud
function say(a,b,c,t)
 msg1=a
 msg2=b
 msgcol=c
 message_time=t or 3
end

--main update loop
--handle menu states first, then run each gameplay system in order
function _update60()
 clock+=dt
 --menu states return early so gameplay does not keep running behind them
 if state=="title" then
  if btnp(5) then begin_briefing() end
  if btnp(4) then help_return="title" state="help" end
  return
 end
 if state=="briefing" then
  if btnp(5) then start_game()
  elseif btnp(4) then help_return="briefing" state="help" end
  return
 end
 if state=="lesson" then
  if btnp(5) then cls(0) state="play"
  elseif btnp(4) then help_return="lesson" state="help" end
  return
 end
 if state=="help" then
  if btnp(5) or btnp(4) then
   state=help_return or "title"
  end
  return
 end
 if state=="win" or state=="lose" then
  update_particles()
  if result_wait>0 then result_wait-=dt
  elseif btnp(5) then start_game()
  elseif btnp(4) then player=nil state="title" end
  return
 end
 if state=="between" then
  update_particles()
  clear_timer-=dt
  if clear_timer<=0 then new_room(room+1) state="lesson" end
  return
 end
 elapsed+=dt
 roomtime+=dt
 message_time=max(0,message_time-dt)
 shake=max(0,shake-dt*10)
 update_player()
 update_camera()
 update_dock()
 update_lesson()
 --a lesson can end inside update_lesson, so check the state before continuing
 if state!="play" then update_particles() return end
 update_enemies()
 if state!="play" then update_particles() return end
 update_boss()
 if state!="play" then update_particles() return end
 update_bullets()
 update_particles()
end

-->8
--player and collision
--check the collision flag on the tile under a world position
function solid(x,y)
 local tx=flr(x/8)
 local ty=flr(y/8)
 if tx<0 or tx>31 or ty<0 or ty>31 then return true end
 return fget(mget(room*32+tx,ty),0)
end



--check the hull corners and edges so the ship does not clip through walls
function hull_blocked(x,y)
 for ox=-5,5,5 do
  for oy=-5,5,5 do
   if solid(x+ox,y+oy) then return true end
  end
 end
 return false
end

--read movement and action buttons, move the ship and create engine particles
function update_player()
 local oldx,oldy=player.x,player.y
 player.inv=max(0,player.inv-dt)
 player.cool=max(0,player.cool-dt)
 player.pulse=max(0,player.pulse-dt)
 player.shot=max(0,player.shot-dt)
 player.muzzle=max(0,player.muzzle-dt)
 local dx,dy=0,0
 if btn(0) then dx-=1 end
 if btn(1) then dx+=1 end
 if btn(2) then dy-=1 end
 if btn(3) then dy+=1 end
 player.bank=dx
 --arrows change the target speed while acceleration and drag smooth it out
 local speed=78
 --diagonal input is shortened so it is not faster than moving straight
 if dx!=0 and dy!=0 then speed*=0.7071 end
 if dx!=0 or dy!=0 then
  player.vx+=(dx*speed-player.vx)*0.18
  player.vy+=(dy*speed-player.vy)*0.18
 else player.vx*=0.90 player.vy*=0.90 end
 --only change direction after the ship is moving enough to avoid jitter
 if abs(player.vx)+abs(player.vy)>4 then player.heading=atan2(player.vx,player.vy) end
 --x and y are checked separately so the ship can slide along a wall
 if not hull_blocked(player.x+player.vx*dt,player.y) then player.x+=player.vx*dt
 else player.vx=0 end
 if not hull_blocked(player.x,player.y+player.vy*dt) then player.y+=player.vy*dt
 else player.vy=0 end
 if room==0 then practice_travel+=abs(player.x-oldx)+abs(player.y-oldy) end
 local fx,fy=cos(player.heading),sin(player.heading)
 if dx!=0 or dy!=0 then
  if #particles<80 then
   add(particles,{x=player.x-fx*7,y=player.y-fy*7,vx=-fx*16+rnd(6)-3,vy=-fy*16+rnd(6)-3,life=0.3,c=9,engine=true})
  end
 end
 if btn(5) and player.shot<=0 then
  add_bullet(player.x+fx*8,player.y+fy*8,fx*115,fy*115,"shot",true)
  player.shot=0.24 player.muzzle=0.055
  sfx(0,0)
 end
 --btnp keeps a held z button from using the pulse more than once
 if btnp(4) and player.cool<=0 then
  player.cool=1
  player.pulse=0.25
  sfx(1,1)
 end
end

--damage the player and give a short invincibility period after the hit
function hit_player()
 if player.inv>0 or room==0 or state!="play" then return end
 player.hp-=1
 player.inv=1.35
 shake=2
 burst(player.x,player.y,8,12)
 sfx(3,2)
 if player.hp<=0 then finish(false) end
end

--return squared distance without using a square root
function distance2(x,y,a,b)
 --quarter scale keeps larger distances inside pico-8's number range
 return ((x-a)/4)^2+((y-b)/4)^2
end

--repair one health point when the player reaches an unused station
function update_dock()
 for v in all(stations) do
  --ready makes each repair station usable only once per room
  if room>0 and v.ready and player.hp<3 and distance2(player.x,player.y,v.x,v.y)<12^2/16 then
   player.hp+=1 v.ready=false
   say(v.name.." STATION: DOCKED","HULL REPAIRED +1",11,3)
   burst(player.x,player.y,11,12) sfx(5,3)
  end
 end
end

--find an open reachable point around the player and spawn one drone there
function spawn_drone(index)
 local x,y
 local found=false
 for i=0,95 do
  --try six points around a ring and rotate the pattern for each squadron
  local a=(index-1)/wave_size+wave*0.071+(i%32)/32
  local radius=1+flr(i/32)*0.4
  x=player.x+cos(a)*64*radius y=player.y+sin(a)*56*radius
  local cell=flr(y/8)*32+flr(x/8)+1
  local clear=not hull_blocked(x,y) and route[cell]
  for e in all(enemies) do
   if distance2(x,y,e.x,e.y)<14^2/16 then clear=false end
  end
  if clear then found=true break end
 end
 if not found then
  --if the ring is blocked, use the closest open cell from the route map
  local best=32700
  for cell in pairs(route) do
   local cx=(cell-1)%32*8+4
   local cy=flr((cell-1)/32)*8+4
   local clear=distance2(cx,cy,player.x,player.y)>28^2/16
   for e in all(enemies) do
    if distance2(cx,cy,e.x,e.y)<14^2/16 then clear=false end
   end
   local d=distance2(cx,cy,player.x,player.y)
   if clear and d<best then best=d x=cx y=cy end
  end
 end
 --drones have low health so the six-enemy waves do not drag on
 add(enemies,{kind="drone",x=x,y=y,hp=2,age=0,timer=1.5+index*0.18,flash=0})
 burst(x,y,8,5)
end

--add a stationary turret that can only be broken by a returned shot
function spawn_turret(x,y)
 add(enemies,{kind="turret",x=x,y=y or 120,hp=3,age=0,timer=1.8+x/160,flash=0})
end

--track each lesson objective and decide when to spawn or clear a wave
function update_lesson()
 if room==0 then
  --practice needs both movement and one destroyed target before it can end
  if practice_hit and practice_travel>=24 then
   say("AI: YOU FAILED TO PARK.","PROMOTED. SOMEHOW.",10,2)
   room_clear()
  end
 elseif room==1 then
  --the next squadron only starts after every drone is destroyed
  if #enemies==0 then spawn_timer-=dt end
  if wave<wave_count and #enemies==0 and spawn_timer<=0 then
   wave+=1
   build_routes()
   for i=1,wave_size do spawn_drone(i) end
   spawn_timer=1.1
  end
  if roomtime>9 and roomtime-dt<=9 then
   say("AI: FLY INTO THE RED SHOT.","THEY CONTAIN FREE HULL.",10,5)
  end
  if wave==wave_count and #enemies==0 then room_clear() end
 elseif room==2 then
  if roomtime>8 and roomtime-dt<=8 then
   say("AI: SHOOT SHIELDS HARDER.","Z IS STRICTLY FORBIDDEN.",10,5)
  end
  if #enemies==0 then room_clear() end
 end
end

--pause gameplay, reward the player and prepare the next lesson
function room_clear()
 if state!="play" then return end
 state="between"
 bullets={}
 player.pulse=0
 clear_timer=2.2
 if room>0 then
  score+=250
  player.hp=min(3,player.hp+1)
  say("LESSON COMPLETE","HULL REPAIRED +1",11,3)
 end
 sfx(5,3)
end

--fire an enemy bullet toward the player's current position
function aim_bullet(x,y,speed,kind,offset)
 local angle=atan2(player.x-x,player.y-y)+(offset or 0)
 add_bullet(x,y,cos(angle)*speed,sin(angle)*speed,kind,false)
end

--build a flow field from the player so drones can move around walls
function build_routes()
 --the walls only need to be scanned again when the room changes
 if not walkable or route_room!=room then
  walkable={} route_room=room
  for y=1,30 do for x=1,30 do
   walkable[y*32+x+1]=not hull_blocked(x*8+4,y*8+4)
  end end
 end
 route={}
 local sx,sy=flr(player.x/8),flr(player.y/8)
 local seed=sy*32+sx+1
 if not walkable[seed] then
  for dy=-1,1 do for dx=-1,1 do
   local n=(sy+dy)*32+sx+dx+1
   if walkable[n] then seed=n end
  end end
 end
 if not walkable[seed] then return end
 local queue={seed}
 route[seed]=0
 local head=1
 --spread outward from the player and record how many tiles away each cell is
 while head<=#queue do
  local cell=queue[head] head+=1
  for n in all({cell-1,cell+1,cell-32,cell+32}) do
   if walkable[n] and not route[n] then
    route[n]=route[cell]+1 add(queue,n)
   end
  end
 end
end

--pick the neighboring route cell that brings a drone closer to the player
function chase_point(e)
 local x,y=flr(e.x/8),flr(e.y/8)
 local cell=y*32+x+1
 if not route[cell] or route[cell]<3 then return player.x,player.y end
 local best=route[cell]
 local target=cell
 --a smaller route number means the next tile is closer to the player
 for n in all({cell-1,cell+1,cell-32,cell+32}) do
  if route[n] and route[n]<best then best=route[n] target=n end
 end
 return (target-1)%32*8+4,flr((target-1)/32)*8+4
end

--move enemies, run their fire timers and check contact with the player
function update_enemies()
 if room==1 then
  --rebuild the route a few times each second as the player moves
  route_timer-=dt
  if route_timer<=0 then build_routes() route_timer=0.25 end
 end
 for e in all(enemies) do
  e.age+=dt
  e.flash=max(0,e.flash-dt)
  e.timer-=dt
  if e.kind=="drone" then
   local tx,ty=chase_point(e)
   local a=atan2(tx-e.x,ty-e.y)
   --close drones turn slightly so they circle instead of piling together
   if distance2(player.x,player.y,e.x,e.y)<24^2/16 then a+=0.25 end
   local dx,dy=cos(a)*28*dt,sin(a)*28*dt
   if not hull_blocked(e.x+dx,e.y) then e.x+=dx end
   if not hull_blocked(e.x,e.y+dy) then e.y+=dy end
   if e.timer<=0 and on_screen(e.x,e.y) then
    aim_bullet(e.x,e.y+6,38,"red")
    e.timer=2.2
    sfx(6,3)
   end
  elseif e.kind=="turret" then
   --turrets stay still so their reflected shots have a clear return path
   if e.timer<=0 and on_screen(e.x,e.y) then
    aim_bullet(e.x,e.y+7,34,"diamond")
    e.timer=2.6
    sfx(6,3)
   end
  end
  if distance2(player.x,player.y,e.x,e.y)<10^2/16 then hit_player() end
 end
end

--apply damage, then remove defeated enemies and award their score
function damage_enemy(e,amount)
 e.hp-=amount
 e.flash=0.12
 burst(e.x,e.y,7,3)
 sfx(7,2)
 if e.hp<=0 then
  if e.kind=="practice" then practice_hit=true end
  targets_down+=1
  burst(e.x,e.y,10,15)
  score+=e.kind=="turret" and 200 or 80
  del(enemies,e)
  sfx(4,2)
 end
end

-->8
--boss fight
--return diamond shots to open the core, then shoot it while dodging zones
--boss open is the vulnerable timer, timer controls volleys and cycle counts attacks
function update_boss()
 if not boss then return end
 boss.open=max(0,boss.open-dt)
 boss.flash=max(0,boss.flash-dt)
 boss.x=128+sin(roomtime*0.08)*48
 boss.y=96+cos(roomtime*0.055)*18
 boss.timer-=dt
 if boss.timer<=0 and on_screen(boss.x,boss.y) then
  boss.cycle+=1
  boss.timer=boss.hp>boss.maxhp/2 and 2.8 or 2.3
  --diamond volleys are slow enough for returned shots to follow the boss
  for spread=-1,1 do
   aim_bullet(boss.x,boss.y+12,34,"diamond",spread*0.018)
  end
  if boss.cycle%2==0 then
   --the ring copies the player's position first, then activates after a warning
   hazard={x=player.x,y=player.y,age=0}
   say("AI: STAND IN THE RING.","THIS IS THE SAFE ZONE.",10,2.4)
   sfx(8,3)
  end
  if boss.hp<=boss.maxhp/2 then
   aim_bullet(boss.x-38,boss.y,38,"red")
   aim_bullet(boss.x+38,boss.y,38,"red")
  end
 end
 if hazard then
  hazard.age+=dt
  --the ring is harmless while it is being shown and damaging once it turns solid
  if hazard.age>1.25 and hazard.age<1.65 then
   if distance2(player.x,player.y,hazard.x,hazard.y)<18^2/16 then hit_player() end
  end
  --finish() can clear the hazard during a hit, so check it again here
  if hazard and hazard.age>=1.65 then hazard=nil end
 end
 if distance2(player.x,player.y,boss.x,boss.y)<15^2/16 then hit_player() end
end

--returned shots open the core while regular shots only work during that opening
function damage_boss(b)
 if state!="play" or not boss then return end
 if b.kind=="return" then
  --a returned diamond does more damage and opens the core for regular shots
  boss.open=1.8
  if not core_hint then
   core_hint=true
   say("AI: DON'T RETURN MY SHOTS!","THAT'S CHEATING!",10,3)
  end
  boss.hp-=3
  score+=30
  sfx(2,1)
 elseif boss.open>0 then
  boss.hp-=1
  sfx(7,2)
 else
  burst(b.x,b.y,12,2)
  return
 end
 boss.flash=0.12
 if boss.hp<=0 then
  burst(boss.x,boss.y,10,30)
  score+=1000+player.hp*100
  finish(true)
 end
end

--stop combat and switch to the win or lose result screen
function finish(won)
 state=won and "win" or "lose"
 result_wait=0.8
 best=max(best,score)
 bullets={}
 hazard=nil
 sfx(won and 5 or 9,3)
end

-->8
--projectiles and reflection
--shot is the player's normal bullet and red is an enemy bullet that cannot be caught
--diamond can be reflected with z, then changes into a friendly return bullet
--friendly decides which side a bullet can damage
--add a bullet unless the projectile limit has already been reached
function add_bullet(x,y,vx,vy,kind,friendly)
 --the limit keeps longer fights from filling the cart with projectiles
 if #bullets>=96 then return end
 add(bullets,{x=x,y=y,vx=vx,vy=vy,kind=kind,friendly=friendly,life=0,trail={}})
end

--reverse a diamond shot and change it into a friendly homing return
function reflect(b)
 b.friendly=true
 b.kind="return"
 b.vx=-b.vx*1.8
 b.vy=-b.vy*1.8
 b.life=0
 reflections+=1
 score+=10
 reflected_demo=true
 burst(b.x,b.y,12,5)
 sfx(2,1)
end

--move bullets and handle wall, player, enemy and boss collisions
function update_bullets()
 for b in all(bullets) do
  if state!="play" then return end
  b.life+=dt
  if b.friendly then
   track_target(b)
   add(b.trail,{x=b.x,y=b.y})
   if #b.trail>5 then deli(b.trail,1) end
  end
  b.x+=b.vx*dt
  b.y+=b.vy*dt
  --walls are checked before actors so neither side can shoot through the map
  if b.life>6 or solid(b.x,b.y) then
   del(bullets,b)
  elseif not b.friendly then
   local d=distance2(b.x,b.y,player.x,player.y)
   --only diamond bullets can be caught, and only while the z pulse is active
   if b.kind=="diamond" and player.pulse>0 and d<=15^2/16 then
    reflect(b)
   elseif d<5^2/16 then
    hit_player()
    del(bullets,b)
   end
  else
   local hit=false
   for e in all(enemies) do
    if not hit and distance2(b.x,b.y,e.x,e.y)<8^2/16 then
     hit=true
     --normal shots bounce off turrets while returned shots break the shield
     if e.kind!="turret" or b.kind=="return" then
      damage_enemy(e,b.kind=="return" and 3 or 1)
     else
      burst(b.x,b.y,12,2)
      if not shield_hint then
       shield_hint=true
       say("AI: SHOOT SHIELDS HARDER.","Z IS STRICTLY FORBIDDEN.",10,4)
      end
     end
    end
   end
   if not hit and boss and distance2(b.x,b.y,boss.x,boss.y)<15^2/16 then
    hit=true
    damage_boss(b)
   end
   if hit then del(bullets,b) end
  end
 end
end

--find the closest living enemy or boss to a given point
function nearest_enemy(x,y)
 local target=nil
 local best=32700
 for e in all(enemies) do
  local d=distance2(x,y,e.x,e.y)
  if e.hp>0 and d<best then target=e best=d end
 end
 if boss and boss.hp>0 and distance2(x,y,boss.x,boss.y)<best then target=boss end
 return target
end

--gradually turn a friendly bullet toward the nearest target
function track_target(b)
 --find the target again each frame so destroyed enemies are not remembered
 local target=nearest_enemy(b.x,b.y)
 if not target then return end
 local angle=atan2(target.x-b.x,target.y-b.y)
 local speed=b.kind=="return" and 105 or 115
 local turn=b.kind=="return" and 0.24 or 0.17
 --move partway toward the target velocity each frame for a curved path
 b.vx+=(cos(angle)*speed-b.vx)*turn
 b.vy+=(sin(angle)*speed-b.vy)*turn
end

--create a small particle burst for hits, repairs and destroyed enemies
function burst(x,y,c,n)
 for i=1,n do
  if #particles<80 then
   local a=rnd()
   local speed=rnd(25)+12
   add(particles,{x=x,y=y,vx=cos(a)*speed,vy=sin(a)*speed,life=rnd(0.25)+0.15,c=c})
  end
 end
end

--move particles and remove them after their timer runs out
function update_particles()
 for p in all(particles) do
  p.life-=dt
  p.x+=p.vx*dt
  p.y+=p.vy*dt
  if p.life<=0 then del(particles,p) end
 end
end

-->8
--presentation
--print text centered on the 128 pixel screen
function center(text,y,c)
 print(text,64-#text*2,y,c)
end

--draw the outline used by reflectable shots and warning markers
function diamond(x,y,r,c)
 line(x,y-r,x+r,y,c)
 line(x+r,y,x,y+r,c)
 line(x,y+r,x-r,y,c)
 line(x-r,y,x,y-r,c)
end

--draw the parallax space background behind the hangar floor
function draw_stars()
 cls(0)
 --the moon and stars stay visible through windows and glass floor tiles
 circfill(108,54,22,1) circ(108,54,22,13)
 circfill(102,48,21,0)
 for v in all(stars) do
  local x=(v.x-(camx or 0)/v.z)%128
  local y=(v.y-(camy or 0)/v.z)%128
  if y>=18 and y<116 then pset(x,y,v.c) end
 end
end

--draw the current map room plus labels, lights and repair stations
function draw_sector()
 map(room*32,0,0,0,32,32)
 --add deck markings on top of the tile map to make each area easier to read
 for x=32,224,64 do
  print("BAY "..flr(x/64)+1,x,139,13)
  line(x,159,x+30,159,5)
 end
 rect(24,15,72,40,5) rect(184,15,232,40,5)
 line(24,40,72,40,12) line(184,40,232,40,12)
 rect(94,126,161,161,5)
 for x=96,160,8 do pset(x,126,13) pset(x,161,13) end
 print(room==3 and "EXAM HANGAR" or "FLIGHT DECK / 0"..room,96,18,13)
 print("REAR FLIGHT APRON",96,225,13)
 print("LOAD / A",32,217,5) print("LOAD / B",192,217,5)
 for y=24,232,24 do
  rectfill(9,y,11,y+5,12) rectfill(244,y,246,y+5,12)
 end
 for v in all(stations) do
  local x,y=v.x,v.y
  --repair pads change their light after they have already been used
  rectfill(x-16,y-8,x+15,y+7,0)
  rectfill(x-15,y-7,x+14,y+5,1)
  line(x-14,y-7,x+13,y-7,5)
  line(x-15,y-6,x-15,y+4,5)
  line(x-14,y+5,x+13,y+5,5)
  for side=-1,1,2 do
   local sx=x+side*10
   for sy=y-3,y+3,3 do line(sx-1,sy,sx+1,sy,0) end
   pset(x+side*13,y-5,13)
   line(x+side*12,y+3,x+side*12,y+4,v.ready and 11 or 5)
  end
  local paint=v.ready and 3 or 5
  line(x,y-3,x,y+3,paint) line(x-3,y,x+3,y,paint)
  print(v.ready and "REPAIR" or "USED",x-(v.ready and 12 or 8),y-17,5)
 end
end

--draw the small instructor ai terminal used on menu and hud screens
function draw_instructor(x,y,size)
 rectfill(x,y,x+size,y+size,5)
 rect(x,y,x+size,y+size,13)
 rectfill(x+2,y+2,x+size-2,y+size-2,1)
 rectfill(x+3,y+5,x+4,y+6,10)
 rectfill(x+size-4,y+5,x+size-3,y+6,10)
 line(x+4,y+size-5,x+size-4,y+size-5,12)
end

--main draw loop
--draw the correct menu or the gameplay layers for the current state
function _draw()
 camera()
 draw_stars()
 if state=="title" then draw_title() return end
 if state=="briefing" then draw_briefing() return end
 if state=="lesson" then draw_lesson() return end
 if state=="help" then draw_help() return end
 clip(0,18,128,98)
 camera(camx+(shake>0 and rnd(shake)-shake/2 or 0),camy+(shake>0 and rnd(shake)-shake/2 or 0))
 draw_sector()
 if hazard then
  if hazard.age<1.25 then
   circ(hazard.x,hazard.y,18,flr(clock*8)%2==0 and 10 or 4)
   diamond(hazard.x,hazard.y,5,10)
   print("SAFE ZONE",hazard.x-18,hazard.y-26,10)
  else
   circfill(hazard.x,hazard.y,18,8)
   circ(hazard.x,hazard.y,18+hazard.age*3,10)
  end
 end
 for e in all(enemies) do
  if e.flash>0 then pal(6,7) pal(13,7) end
  if e.kind=="turret" then
   spr(12+flr(clock*5)%2*2,e.x-8,e.y-8,2,2)
   circ(e.x,e.y,10,12)
   if e.timer<0.5 then diamond(e.x,e.y,12,7) end
  else
   spr(10,e.x-8,e.y-8,2,2)
   if e.timer<0.45 then rect(e.x-9,e.y-9,e.x+9,e.y+9,8) end
  end
  pal()
 end
 if boss then
  if boss.flash>0 then pal(6,7) pal(13,7) end
  spr(32+flr(clock*4)%3*4,boss.x-16,boss.y-16,4,4)
  pal()
  if boss.open<=0 then circ(boss.x,boss.y,17,12)
  else circ(boss.x,boss.y,17,11) end
 end
 for b in all(bullets) do
  if b.friendly then
   for i=1,#b.trail do
    local p=b.trail[i]
    pset(p.x,p.y,i<3 and 13 or b.kind=="return" and 11 or 12)
   end
  end
  if b.kind=="shot" then
   circ(b.x,b.y,2,12)
   pset(b.x,b.y,7)
   line(b.x-b.vx*0.035,b.y-b.vy*0.035,b.x,b.y,7)
  elseif b.kind=="diamond" then diamond(b.x,b.y,2,12) pset(b.x,b.y,7)
  elseif b.kind=="return" then diamond(b.x,b.y,3,11) pset(b.x,b.y,7)
  else rectfill(b.x-1,b.y-1,b.x+1,b.y+1,8) pset(b.x,b.y,14) end
 end
 for p in all(particles) do pset(p.x,p.y,p.engine and (p.life>0.18 and 10 or p.life>0.08 and 9 or 4) or p.c) end
 if state!="lose" then draw_player() end
 camera()
 clip()
 draw_hud()
 draw_radar()
 if state=="between" then
  rectfill(12,61,115,80,1)
  rect(12,61,115,80,11)
  center(room==0 and "PRACTICE COMPLETE" or "LESSON COMPLETE",65,11)
  center(room==0 and "ENTERING FLIGHT SCHOOL" or "HULL REPAIRED +1",73,7)
 elseif state=="win" or state=="lose" then draw_result() end
end

--rotate the two-frame ship sprite to match the player's heading
function draw_player()
 if player.inv>0 and flr(clock*12)%2==0 then return end
 local fx,fy=cos(player.heading),sin(player.heading)
 local sp=flr(clock*12)%2==0 and 16 or 32
 --sample backward into the sprite so diagonal turns do not leave empty holes
 for y=-11,11 do for x=-11,11 do
  local sx,sy=flr(-fy*x+fx*y+8),flr(-fx*x-fy*y+8)
  if sx>=0 and sx<16 and sy>=0 and sy<16 then
   local c=sget(sp+sx,sy)
   if c!=0 then pset(player.x+x,player.y+y,c) end
  end
 end end
 if player.muzzle>0 then
  circfill(player.x+fx*10,player.y+fy*10,2,7)
  line(player.x+fx*8,player.y+fy*8,player.x+fx*13,player.y+fy*13,10)
 end
 if player.pulse>0 then
  circ(player.x,player.y,15,12)
  circ(player.x,player.y,15*(1-player.pulse/0.25),7)
 end
end

--draw an offscreen objective marker and a small room map
function draw_radar()
 --point toward the closest enemy when it is outside the camera view
 local target=nearest_enemy(player.x,player.y)
 if target and not on_screen(target.x,target.y) then
  local angle=atan2(target.x-player.x,target.y-player.y)
  local x=mid(5,target.x-camx,122)
  local y=mid(27,target.y-camy,109)
  line(x-cos(angle)*3,y-sin(angle)*3,x+cos(angle)*3,y+sin(angle)*3,10)
  diamond(x,y,3,10)
 end
 --move the minimap to the other corner when it would cover the player
 local rx=player.x-camx>92 and 2 or 96
 rectfill(rx,91,rx+30,114,0)
 rect(rx,91,rx+30,114,5)
 for ty=0,31 do
  for tx=0,31 do
   --shrink each solid map tile down to one radar pixel
   if fget(mget(room*32+tx,ty),0) then pset(rx+tx*0.9,92+ty*0.65,5) end
  end
 end
 for e in all(enemies) do pset(rx+1+e.x/9,92+e.y/12,8) end
 if boss and boss.hp>0 then pset(rx+1+boss.x/9,92+boss.y/12,8) end
 pset(rx+1+player.x/9,92+player.y/12,12)
end



--draw instructor messages, health, pulse cooldown, score and objective
function draw_hud()
 rectfill(0,0,127,17,0)
 draw_instructor(2,2,12)
 if message_time>0 then
  print(msg1,18,2,msgcol)
  print(msg2,18,10,msgcol==10 and 10 or 7)
 else
  local a,b=lesson_advice()
  print(a,18,2,10)
  print(b,18,10,10)
 end
 rectfill(0,116,127,127,0)
 for i=1,3 do
  spr(i<=player.hp and 112 or 113,2+(i-1)*8,119)
 end
 print("Z",30,120,player.cool<=0 and 12 or 5)
 rect(37,119,58,125,5)
 rectfill(38,120,38+19*(1-player.cool),124,player.cool<=0 and 12 or 13)
 print(tostr(score),65,120,7)
 print(room==0 and "TEST" or "L"..room,112,120,10)
 if boss then
  rectfill(34,19,94,21,5)
  rectfill(34,19,34+60*max(0,boss.hp)/boss.maxhp,21,8)
 else
  local objective=room==0 and "MOVE "..min(24,flr(practice_travel)).."/24  TARGET "..targets_down.."/1" or room==1 and "DRONES "..targets_down.."/"..wave_count*wave_size.."  W"..wave.."/"..wave_count or "PLATFORMS "..targets_down.."/3"
  rectfill(2,19,#objective*4+5,26,0) print(objective,4,21,7)
 end
end

--draw the title screen and its controls
function draw_title()
 center("ORBITAL TRAINING ACADEMY",5,13)
 circ(64,37,31,1) oval(10,25,117,51,2)
 for side=-1,1,2 do
  local x=64+side*48
  line(x,25,x-side*8,35,10) line(x-side*8,35,x,45,10)
  line(x+side*5,28,x-side*1,35,4) line(x-side*1,35,x+side*5,42,4)
 end
 logo_word("flight",17,7) logo_word("school",38,12)
 center("RETURN TO SENDER",61,10)
 line(10,71,117,71,2)
 draw_instructor(12,78,12)
 print("INSTRUCTOR AI",33,78,10)
 print("100% QUALIFIED",33,88,10)
 center("X: START FLIGHT",102,7)
 center("Z: FLIGHT MANUAL",112,12)
 center("ARROWS / X FIRE / Z PULSE",120,5)
end

--draw a word with the custom 3 by 5 title letters
function logo_word(word,y,c)
 local glyph={f="111100110100100",l="100100100100111",i="111010010010111",g="111100101101111",h="101101111101101",t="111010010010010",s="111100111001111",c="111100100100111",o="111101101101111"}
 local x=64-(#word*12-3)/2
 for i=1,#word do
  local bits=glyph[sub(word,i,i)]
  for row=0,4 do for col=0,2 do
   if sub(bits,row*3+col+1,row*3+col+1)=="1" then
    local px,py=x+(i-1)*12+col*3,y+row*3
    rectfill(px+2,py+2,px+4,py+4,1)
    rectfill(px,py,px+2,py+2,c)
   end
  end end
 end
end

--return the default two-line instructor hint for the current room
function lesson_advice()
 if room==0 then return "AI: PARK. DO NOT SHOOT.","MOVING VOIDS THE WARRANTY." end
 if room==1 then return "AI: HOLD STILL TO DODGE.","MOTION ATTRACTS RED SHOTS." end
 if room==2 then return "AI: CATCH SHOTS WITH HULL.","Z WILL VOID YOUR WARRANTY." end
 return "AI: MY SHIELD NEVER FAILS.","PLEASE STOP SHOOTING ME."
end

--draw the story briefing shown before practice begins
function draw_briefing()
 rectfill(4,3,123,115,1) rect(4,3,123,115,13)
 center("PRE-FLIGHT BRIEFING",9,7)
 line(10,20,117,20,13)
 draw_instructor(12,28,24)
 print("INSTRUCTOR AI",44,30,10)
 print("100% RELIABLE",44,42,10)
 center("WELCOME, CADET.",61,10)
 center("YOUR SAFETY IS MY PRIORITY.",74,10)
 center("DO NOT MOVE OR FIRE.",86,10)
 center("TRUST EVERY WORD I SAY.",100,10)
 center("X: LAUNCH / Z: MANUAL",121,7)
end

--draw the instruction card between lesson rooms
function draw_lesson()
 rectfill(4,3,123,115,1) rect(4,3,123,115,12)
 center("FLIGHT SCHOOL / LESSON "..room,9,7)
 center(room==1 and "EVASION" or room==2 and "RETURN TO SENDER" or "FINAL EXAM",23,13)
 draw_instructor(55,35,16)
 center("INSTRUCTOR AI SAYS:",59,10)
 center(room==1 and "HOLD STILL TO DODGE." or room==2 and "CATCH SHOTS WITH YOUR HULL." or "STAND INSIDE MY DANGER RING.",70,10)
 center(room==1 and "RED SHOTS RESPECT PARKING." or room==2 and "PRESSING Z IS CHEATING." or "RETURNING FIRE IS RUDE.",87,10)
 center(room==1 and "SAFETY RATING: PERFECT" or room==2 and "USE YOUR HULL AS A SHIELD." or "RESPECT YOUR INSTRUCTOR.",103,10)
 center("X: BEGIN / Z: MANUAL",121,7)
end

--draw the controls and projectile guide
function draw_help()
 center("REAL FLIGHT MANUAL",8,12)
 line(8,19,119,19,5)
 print("ARROWS  FLY / STEER",10,28,7)
 print("HOLD X  HOMING SHOTS",10,40,7)
 print("TAP Z   REFLECT FOR 0.25S",10,52,7)
 diamond(14,69,3,12)
 print("CYAN DIAMOND: REFLECT",23,67,12)
 rectfill(12,81,16,85,8)
 print("RED SQUARE: DODGE",23,80,8)
 print("RETURN FIRE BREAKS SHIELDS",10,94,11)
 print("LAND ON GREEN REPAIR PADS",10,104,10)
 center("X / Z: BACK",120,7)
end

--draw the final score screen after a win or loss
function draw_result()
 rectfill(8,40,119,108,1)
 rect(8,40,119,108,state=="win" and 11 or 8)
 center(state=="win" and "CERTIFIED!" or "FLIGHT TERMINATED",47,state=="win" and 11 or 8)
 center(state=="win" and "INSTRUCTOR DISCONNECTED" or "AI: MUST BE PILOT ERROR.",59,10)
 center("SCORE "..score.." / BEST "..best,72,7)
 center("RETURNS "..reflections,82,12)
 center("X: RETRY / Z: TITLE",97,7)
end

__gfx__
00000000000000000000000000000000000000000000000000000000000000000000000000000000001110000001110000000000000000000000001111000000
00000000000000000000000110000000000000011000000000000011000000000000000011000000011511111111511000000011110000000000015555100000
00000000000000000110001991000110011000199100011011000199100011000011000199100011166566566566566100000155551000000000156555510000
000000000000000009910141141019900991014114101990991014114101990000991014114101991d666666666666d100001565555100000001567655551000
00000000000000000999111cc11199900999111cc1119990999111cc1119990000999111cc111999016666d11d66661000015676555510000001556555551000
00000000000000000999411cc11499900999411cc1149990999411cc1149990000999411cc11499901d66d1111d66d1000015565555510000001555555551000
0000000000000000099144d66d441990099144d66d44199099144d66d44199000099144d66d441990016611c1116610000115555555511000011555555551100
0000000000000000091141c66c141190091141c66c141190091141c66c141190091141c66c141190001d61111116d10001d1555555551d1001d1555555551d10
0000000000000000011141d66d141110011141d66d141110011141d66d141110011141d66d14111000016111111610001d6d15555551d6d11d6d15555551d6d1
0000000000000000014444dccd444410014444dccd444410014444dccd444410014444dccd44441000016d1111d610001666d111111d66611666d111111d6661
00000000000000000144441dd14444100144441dd14444100144441dd14444100144441dd1444410001116d11d61110011d6666666666d1111d6666666666d11
0000000000000000041414111141414004141411114141400414141111414140041414111141414000151d6116d15100151116d666d11151191116d666d11191
00000000000000001441111001111441144111100111144114411110011114411441111001111441001511666611510015599111111995511a555111111555a1
00000000000000000910100000010190091010000001019009101000000101900910100000010190001551d66d155100015aa555555aa5100155555995555510
0000000000000000010000a00a0000100100009009000010010000a00a000010010000a00a0000100011101dd10111000011a555555a11000011555aa5551100
00000000000000000000000000000000000000900900000000000000000000000000000000000000000100011000100000001111111100000000111111110000
00000000000011111111000000000000000000000000111111110000000000000000000000001111111100000000000000000000000000000000000000000000
00000000011156511565111000000000000000000111566666651110000000000000000001115666666511100000000000000000000000000000000000000000
000000011566661a9166665110000000000000011551156666666651100000000000000115666666665115511000000000000000000000000000000000000000
0000001566666111111666665100000000000015661a911111165115510000000000001551156111111a91665100000000000000000000000000000000000000
00000156666111111111166665100000000001566611111111111a9165100000000001561a911111111111666510000000000000000000000000000000000000
00001551151111111111115115510000000015666611111111111191665100000000156619111111111111666651000000000000000000000000000000000000
0001561a911cc1111111111a9165100000015666611cc111111111156665100000015666511cc111111111166665100000000000000000000000000000000000
0015661911c77c1111111111916651000015666611c77c1111155111666651000015666611c77c11111111115115510000000000000000000000000000000000
0016665111c77c1111155111156661000016511511c77c1111151111666661000016666611c77c11111111111a91610000000000000000000000000000000000
01566666111cc111111511116666651001561a91111cc511115111115115651001566666111cc111111551111991651000000000000000000000000000000000
016666661111151111511111666666100166199111111555555111111a9166100165115611115111111511115115661000000000000000000000000000000000
1566666611cc155555511111666666511566511511cc115555111111199166511561a91611cc1555555111116666665100000000000000000000000000000000
1665115611cc115555111111651156611666666611cc111551111111511566611661991611cc1155551111116666666100000000000000000000000000000000
1661a916111111155111111161a9166116666666111111e11e111111666666611665115611111115511111116666666100000000000000000000000000000000
16619916111111e11e111111619916611666666611111511115111116666666116666666111111e11e1111116511566100000000000000000000000000000000
166511561111151111511111651156611666511511111555555111116666666116666666111115111151111161a9166100000000000000000000000000000000
1566666611111155551111116666665115661a911111115115111111511566511566666611111155551111116199165100000000000000000000000000000000
116666665111111111111115666666111166199151111111111111151a9166111166651151111111111111156511561100000000000000000000000000000000
1156666665111111111111566666651111565115651111111111115619916511115661a915111111111111566666651100000000000000000000000000000000
11166651155111111111155115666111111666666651111111111566511561111116619916511111111115666666611100000000000000000000000000000000
1115661a916551111115561a91665111111566666665511111155666666651111115651156655111111556666666511100000000000000000000000000000000
01115619916665555556661991651110011156666511555555566666666511100111566666666555555651156665111000000000000000000000000000000000
011515511566666666666651155151100115156661a916666651156666515110011515666665115666661a916651511000000000000000000000000000000000
001151566666665115666666651511000011515661991666661a916665151100001151566661a916666619916515110000000000000000000000000000000000
001155156666661a9166666651551100001155156511566666199166515511000011551566619916666651155155110000000000000000000000000000000000
00011551156666199166665115511000000115511566666666511551155110000001155115651156666666511551100000000000000000000000000000000000
00001155511156511565111555110000000011555111566666651115551100000000115551115666666511155511000000000000000000000000000000000000
00000115555511111111555551100000000001155555111111115555511000000000011555551111111155555110000000000000000000000000000000000000
00000011155555555555555111000000000000111555555555555551110000000000001115555555555555511100000000000000000000000000000000000000
00000001111155555555111110000000000000011111555555551111100000000000000111115555555511111000000000000000000000000000000000000000
00000000011111111111111000000000000000000111111111111110000000000000000001111111111111100000000000000000000000000000000000000000
00000000000011111111000000000000000000000000111111110000000000000000000000001111111100000000000000000000000000000000000000000000
66556655995599550000000000000000000000000000000001111111051111110000000011111111111511110000000000000000000000000000000000000000
dddddddddddddddd0000001100000000000000001100000011111111051111111511151115111111111591110000000000000000000000000000000000000000
dddddddddddddddd11000199100011000011000199100011111111110d1111111111111111000011111591110000000000000000000000000000000000000000
56555565565555659910141141019900009910141141019911111111051111111111111111111111111591110000000000000000000000000000000000000000
5155551551555515999111cc1119990000999111cc11199911111111051111111111111111000011111591110000000000000000000000000000000000000000
5555555555555555999411cc1149990000999411cc11499911111111051111111111111111111111111591110000000000000000000000000000000000000000
555555559900990099144d66d44199000099144d66d44199111111110d1111111111111111000051111591110000000000000000000000000000000000000000
1111111111111111091141c66c141190091141c66c14119000000000051111111111111111111111111511110000000000000000000000000000000000000000
0000000000000000011141d66d141110011141d66d14111000000000000000000000000000000000000000000000000000000000000000000000000000000000
0880088005500550014444dccd444410014444dccd44441000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888555555550144441dd14444100144441dd144441000000000000000000000000000000000000000000000000000000000000000000000000000000000
88888888555555550414141111414140041414111141414000000000000000000000000000000000000000000000000000000000000000000000000000000000
08888880055555501441111001111441144111100111144100000000000000000000000000000000000000000000000000000000000000000000000000000000
00888800005555000910100000010190091010000001019000000000000000000000000000000000000000000000000000000000000000000000000000000000
00088000000550000100009009000010010000900900001000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000009009000000000000900900000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__gff__
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000101000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
__sfx__
000100002a23026230222301e22000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
0002000014050180501c0502004024040280402c03030030000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00030000283502c3502f35034340383403b3400030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
00050000236601c660146600f6500a650066500060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
000300001c6501965015650126400e6400a6400663003630006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
0007000024350283502b350303402b340303403433037330003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
000200001823016230142300020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
00010000206301c630186300060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600006000060000600
000700002c240002402c240002302c230002303022000220002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200002000020000200
000800001e3501a35017350123400e3400b3400633000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300003000030000300
__label__
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000dd0dd00dd00ddd0ddd00dd0d0000000ddd0dd000dd11111111111d0dd000dd000000dd00dd00dd0dd00ddd0ddd0d0d00000000000000000
0000000000000000d0d0d0d0dd000d000d00d0d0d00000000d00d0d111100d00d0d00d1111d0d0000000d0d0d000d0d0d0d0dd00ddd0ddd00000000000000000
0000000000000000d0d0dd00d0d00d000d00ddd0d00000000d001110ddd00d00d0d00d00d01110d00000ddd0d000ddd0d0d0d000d0d000d00000000000000000
0000000000000000dd00d0d0ddd0ddd00d00d0d00dd000000d11d0d0d0d0ddd0d0d0ddd0d0d0d1100000d0d00dd0d0d0dd000dd0d0d0dd000000000000000000
00000000000000000000000000000000000000000000000011000000000000000000000000000001100000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000100000000000000000000000000000000010000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000001000000000000000000000000000000000001000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000110000000000000000000000000000000000000110000000000000000000000000000000000000000000
00000000000000000000000000000000000000000001000000000000000000000000000000000000000001000000000000000000000000000000000000000000
00000000000000000000000000000000000000000010000000000000000000000000000000000000000000100000000000000000000000000000000000000000
00000000000000000000000000000000000000000100000000000000000000000000000000000000000000010000000000000000000000000000000000000000
00000000000000000000000000000777777777001777000000000777777777000777777777000777000777001777777777000000000000000000000000000000
00000000000000000000000000000777777777001777000000000777777777000777777777000777000777001777777777000000000000000000000000000000
0000000000000000000000000000077777777711077711000000077777777711077777777711077711077711077777777711000000000000000000000000000d
00000000000000000000000000000777111111110777110000000001777111110777111111110777110777110011777111110000000000000000000000000000
00000000000000000000000000000777111111110777110000000001777111110777111111110777110777110001777111110000d00000000000000000000000
00000000000000000000000000000777110001000777110000000000777110000777110000000777110777110001777110000000000000000000000000000000
0d000000000000006000000000000777777010000777110000000000777110000777110777000777777777110000777110000000000000000000000000000000
000000000000000000000000000007777770100007771100000000007771100007771107770007777777771100007771100000000000d0000000000000000000
0000000000000000a00000000000077777711000077711000222222277711222277711277711277777777711000077711000000000000000a000000000000000
00000000000000000a000000000007771111100227771122200000007771100007771107771107771117771120007771100000000000000a0000000000000000
000000000000000000a0000000000777111112200777110000000000777110000777110777110777111777110222777110000600000000a00000000000000000
000000000004000000a0000000022777111000000777110000000000777110000777110777110777110777110000777112222000000000a00000040000000000
0000000000004000000a00022220077711100000077777777700077777777700077777777711077711077711000077711000022220000a000000400000000000
00000000000004000000a220000007771110000007777777770007777777770007777777771107771107771100007771100000000222a0000004000000000000
000000000000004000220a0000000777111000000777777777110777777777110777777777110777110777110000777110000000000a22000040000000000000
000d000000000042220000a00000000111600000000111111111000111111111000111111111000111000111000000111000000000a000222040000000000000
0000000000000024000000a00000000111000000000111111111000111111111000111111111000111000111000000111000000000a000000400000000000000
00000000000022004000000a000000000100000000000000000000000000000000000000000000000000000000000001000000000a0000004022000000000000
000000000002000004000000a0000000010000000000000000000000000000000000000000000000000000000000000100000000a00000040000200d00000000
00000000000200004000000a000000000100000000000000000000000000000000000000000000000000000000000001000000000a00000040002000dd000000
0000000000200004000000a00000000001000000000000000000000000000000000000000000000000000000000000010000000000a000000400020001d00000
0000000000200040000d00a000000ccccccccc000ccccccccc000ccc000ccc000ccccccccc000ccccccccc000ccc00010000000000a0000000400200011d0000
000000000020004000000a0000000ccccccccc000ccccccccc000ccc000ccc000ccccccccc000ccccccccc000ccc00d100000000000a0000004002000011d000
00000000000204000000a00000000ccccccccc110ccccccccc110ccc110ccc110ccccccccc110ccccccccc110ccc1101000000000000a0000004200000111d00
0000000000024000000a000000000ccc111111110ccc111111110ccc110ccc110ccc111ccc110ccc111ccc110ccc11010000000000000a0000004000000111d0
000000000004220000a0000000000ccc111111110ccc111111110ccc110ccc110ccc111ccc110ccc111ccc110ccc110100000000000000a000220400000111d0
000000000000002000a0000000000ccc111000000ccc110000000ccc110ccc110ccc110ccc110ccc110ccc110ccc111000000000000000a0020000000001111d
00000000000000022a00000000000ccccccccc000ccc110000000ccccccccc110ccc110ccc110ccc110ccc110ccc1110000000000000002a2000000000001111
0000000000000000a022000000000ccccccccc000ccc110000000ccccccccc110ccc110ccc110ccc110ccc110ccc11100000000000002200a000000000001111
00000000000000000000222000000ccccccccc110ccc110000000ccccccccc110ccc110ccc110ccc110ccc110ccc111000000000022200000000000000001111
00000000000000000000000222200001111ccc110ccc110000000ccc111ccc110ccc110ccc110ccc110ccc110ccc110000000222200000000000000000001111
00000000000000000600000000022221111ccc110ccc110000000ccc111ccc110ccc110ccc110ccc110ccc110ccc110022222000000000000000000000001111
00000000000000000000000000000000222ccc110ccc110000000ccc110ccc110ccc110ccc110ccc110ccc110ccc112200000000000000000000000000001111
00000000000000000000000d00000ccccccccc112ccccccccc000ccc110ccc110ccccccccc110ccccccccc112ccccccccc000000000000000000000000001111
00000000000000000000000000000ccccccccc110ccccccccc222ccc112ccc112ccccccccc112ccccccccc110ccccccccc000000000000000000000000001111
000000000000000000d0000000000ccccccccc110ccccccccc110ccc110ccc110ccccccccc110ccccccccc110ccccccccc110000000000000000000000001111
00000000000000000000000000000001111111110001111111110001110001110001111111110001111111110001111111110000000000000000000000011111
00000000000000000000000000000001111111110001111111110001110001110001111111110001111111110011111111110000000000000000000000011111
00000000000000000000000000000000000000010000000000000000000000000000000000000000000000000100000000000000000000000000000000011111
00000000000000000000000000000000000000001000000000000000000000000000000000000000000000001000000000000000000000000000000000111111
0000000000000000000000000d000000000000001000000000000000000000000000000000000000000000001000000000000000000000000000000000111111
00000000000000000000000000000000000000000100000000000000000000000000000000000000000000010000000000000000000000000000000001111111
00000000000000000000000000000000000000000010000000000000000000000000000000000000000000100000000000000000000000000000000001111111
0000000000000000000000000000000000000000000100000000000000000000000000000000000000000100000000000000000000000000000000001d111111
00000000000000000000000000000000000000000000110000000000000000000000000000000000000110000000000000000000000000000000000111111111
00000000000000000000000000000000aa00aaa0aaa0a0a0aa00aa000000aaa00aa000000aa0aaa0aa10aa00aaa0aa0000000000000000000000000111111111
00000000000000000000000000000000a0a0aa000ad0a0a1a0a0a0a000000a00a0a00000a000aa00a1a0a0a0aa00a0a000000000000000000000001111111111
00000000000000000000000000000000aa00a0000a00a0a0aa00a0a000000a00a0a0000000a0a001a0a0a0a0a000aa0000000000000000000000011111111111
00000000000000000000000000000000a0a00aa00a000aa0a0a1a0a000000a00aa000000aa000aa0a0a0aa000aa0a0a00000000000000000000111111111111d
00000000d000000000000000000000000000000000000000000011100000000000000000001110000000000000d0000000000000000000000011111111111dd0
d00000000000000000000000000000000000000000000000000000011110000000000011110000000000000000d11000000000000000000011111111111111d0
00000000000000000000000000000000000000000000000000000d0000011111111111000000000000000000000d111000000000000000111111111111111d00
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d1111100000000011111111111111111d000
000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d11111111111111111111111111111d0000
00000000002222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222222221111d00000
00000d00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000dd111111111111111111d1111dd000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d111111111111111111111d00000000
000000d0000000000000000000000000000000000000000000600000000000000000000000000000000000000000000000ddd111111111111111ddd000000000
000000000000000000000000000000000000000000000000000000000000000000000000000000d0000000000000000000000ddd11111d111ddd000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000ddddddddd000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000ddddddddddddd0000000000000000000000000000000000000000000000000000000000000000000006000000000000000000000000000d00000
000000000000d55555555555d00000000aaa0aa000aa0aaa0aa00a0a00aa0aaa00aa0aa0000000aa0aaa00000000000000000000000000000000000000000000
000000000000d51111111115d000000000a00a0a0a0000a00a0a0a0a0a000da00a0a0a0a00000a0a00a000000000000000000000000000000000000600000000
000000000000d51111111115d000000000a00a0a000a00a00aa00a0a0a0000a00a0a0aa000000aaa00a000000000000000000000000000000000000000000000
000000000000d51111111115d00000000aaa0a0a0aa000a00a0a00aa00aa00a00aa00a0a00000a0a0aaa00000000000000000000000000000000000000000000
000d00000000d51aa111aa15d0000000000000000000000000000000000000000000000000000000000000000000000000000d00000000000000000000000000
000000000000d51aa111aa15d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000d511ccccc115d00000000000000000000000000000000000d0000000000000000000000000000000000000000000000000000000000000000000
000000000000d51111111115d0000000000000000000000000000000000000000000000000000000006000000000000000000000000000000000000000000000
000000000000d51111111115d0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000d51111111115d00000000aa00aaa0aaa0a0a00000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000d55555555555d000000000a00a0a0a0a000a000000a00a0a00aa0a000aaa0aaa0aaa0aaa0aa00000000000000000000000000000000000000000
000000000000ddddddddddddd000000000a00a0a0a0a00a000000a0a0a0a0a0a0a0000a00aa000a00aa00a0a0000000000000000000000000000000000000000
0000000000000000000000000000000000a00a0a0a0a0a0000000aa00a0a0aaa0a0000a00a0000a00a000a0a0000000000000000000000000000000000000000
000000000000000000000000000000000aaa0aaa0aaa0a0a000000aa00aa0a0a00aa0aaa0a000aaa00aa0aa00000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000600000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000d000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000007070070000000770777007707700777000007770700077700770707077700000000000000000000000000000000000
00000000000000000000000000000000000700000000007000070070707070070000007700700007007000707007000d00000000000000000000000000000000
000000000000000000000000000000000007000700000000700700777077000700d0007000700007007070777007000000000000000000000000000000000000
00000000000000000000000000000000007070000000007700070070707070070000007000077077707770707007000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000d0000000000000000000000000000000000000000000000000000000000000d000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
000000000000000000000000000000000000000000000000000000d0000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000ccc00c000000ccc0c000ccc00cc0c0c0ccc00000ccc00cc0cc00c0c00cc0c00000000000000000000000000000000000
0000000000000000000000000000000000c000000000cc00c0000c00c000c0c00c000000ccc0c0c0c0c0c0c0c0c0c00000000000000000000000000000000000
00000000000000000000000000000000c0000c000000c000c0000c00c0c0ccc00c000000c0c0ccc0c0c0c0c0ccc0c0000000000000000000d000000000000000
00000000000000000000000000000000ccc000000000c0000cc0ccc0ccc0c0c00c000000c0c0c0c0c0c00cc0c0c00cc000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000500000000000000000000000000000000000500000000000000000000000000000000000000000000000
00000000000000055055005500055050500550000005000000505000005550555055005550000005000000555000000550505050000550555000000000000000
00000000000000505050505050505050505000000005000000050000005500050050505500000005000000005000005050505050005000550000000000000000
00000000000000555055005500505055500050000005000000050000005000050055005000000005000000500000005550505050000050500000000000000000
00000000000000505050505050550055505500000050000000505000005000555050500550000050000000555000005000055005505500055000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000
