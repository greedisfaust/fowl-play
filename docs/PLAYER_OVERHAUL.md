# Player Overhaul Audit - Phase 0

## 1. Current Player Scene Structure

**Main Player Node:** `Player` (extends CharacterBody3D)
- Contains:
  - `Head` (Node3D) - contains Camera3D and RayCast3D
  - `Body` (Node3D) - physical representation
  - `BodyPhys` (Node3D) - limp physics simulation child
  - `Hands` (Node3D) - procedural hands component
  - `Focus` (Node3D) - interaction targeting system
  - `Overlay` (Node3D) - UI overlay system

## 2. Hands API Callers (all instances in codebase)

### 2.1 Direct Calls
- `hands.reach(p)` - Line 258 in `_try_interact()` (interaction system)
- `hands.reach(p)` - Line 646 in `interact()` (carry pickup interaction)
- `hands.set_hover(on, point)` - Line 596 in `_process()` (hover state)
- `hands.set_hover(on, point)` - Line 600 in `_process()` (hover state update)
- `hands.set_speed(speed)` - Line 602 in `_process()` (speed-based sway)
- `hands.reach(Vector3.ZERO)` - Line 452 in `_net_punch_hitbox()` (visual reset)
- `hands.reach(point)` - Line 647 in `_net_reach()` (networked reach update)
- `hands.update_hover_point(point)` - Line 602 in `_net_hover_point()` (networked hover update)

### 2.2 Indirect/Contextual Calls
- `hands` reference stored in `player.gd` (lines 39, 166) - used by combat, focus, and other systems
- `hands` used in combat systems for visual feedback (parry guard, hitbox positioning)

## 3. Body/BodyPhys/Limp State Consumers

### 3.1 Body Phys Components
- `body_phys: BodyPhys = $BodyPhys` (line 33) - primary limp physics controller
- `body_phys.begin_limp()` (line 90) - initiates limp state
- `body_phys.end_limp()` (lines 119, 120) - completes limp state
- `body_phys.last_synced_transform` (line 112) - authoritative limp position

### 3.2 Limp State Machine Consumers
- `state.is_limp()` (lines 702, 717) - main limp state check
- `state.limp_phase` (lines 88, 124, 125) - specific limp sub-states
- `state.set_limp_phase()` (lines 88, 125) - state transitions

### 3.3 Camera Flow
- `_limp_puppet()` (line 544) - camera follows body during limp
- `head.position.y = _head_rest_y` (line 127) - camera reset on recovery
- `head.global_position = body_phys.global_position + body_phys.global_basis * Vector3(0.0, _head_rest_y, 0.0)` (line 555) - camera anchoring during limp

## 4. Limp/Carry/Camera Flow

### 4.1 Limp Initiation
1. `host_knock_down()` → `_apply_limb_begin()` (line 71)
2. `_apply_limb_begin()` → `state.transition_to(LIMP)` (line 88)
3. `body_phys.begin_limp()` (line 90)
4. `_net_limb_begin()` RPC sent (line 98)

### 4.2 Limp Recovery
1. `_on_limb_recovered()` → `body_phys.end_limp()` (line 119)
2. `_apply_recovery()` → `state.transition_to(IDLE)` (line 125)
3. Camera reset to `_head_rest_y` (line 127)
4. `_net_limb_end()` RPC sent (line 138)

### 4.3 Camera Behavior
- Normal: follows body position, camera rotation independent
- Limp: `_limp_puppet()` follows body_phys position and basis
- Camera anchoring: head position offset from body_phys position

## 5. Current RPC List Touching Limp State

- `_net_limb_begin(start_pos, launch, seconds)` (line 98) - sends limp begin event
- `_net_limb_end(final_pos)` (line 138) - sends limp end event
- `_on_limb_recovered(body)` (line 107) - handles limp recovery signal
- `_apply_recovery(final)` (line 118) - host-side recovery logic

## 6. Identified Bugs and Risks

### 6.1 Critical Bugs
1. **Double Hands Instantiation** (Line 160-168 in `_ready()`):
   - `hands = Hands.new()` called twice
   - First instance created at line 160, discarded at line 166
   - Potential resource leak and inconsistent state

2. **Remote Punch Reach Failure** (Line 447-452 in `_net_punch_hitbox()`):
   - Uses `puncher.has_node("Hands")` but hands live under `Head` or `Head/Camera3D`
   - Remote clients may not see punch reach visuals

3. **Parry Path Guessing** (Line 494-499 in `_net_parry()`):
   - Uses fallback path guessing (`get_node_or_null("Head/Hands")`) instead of stored `p.hands` reference
   - May fail to find hands node on remote players

### 6.2 Minor Issues
1. **Input Locking During Limp** (line 91):
   - `input_locked = true` set during limp, but may not be properly cleared
   
2. **Camera Reset on Recovery** (line 127):
   - Hard reset of head position may cause visual pop

## 7. Phase 0 Plan

### 7.1 Immediate Fixes (High Priority)
1. Fix double Hands instantiation in `_ready()` (lines 160-168)
2. Replace fallback path guessing in `_net_parry()` with stored `p.hands` reference
3. Verify `_net_punch_hitbox()` handles hands location correctly

### 7.2 Audit Tasks (To Complete Before Phase 1)
1. Map complete player scene hierarchy with all node relationships
2. Document all Hands API callers with file/line references
3. Document all BodyPhys/limp state consumers with file/line references
4. Document complete limp/carry/camera flow with sequence diagram
5. Document all RPCs touching limp state with purpose and validation

### 7.3 Deliverables
1. Updated `docs/PLAYER_OVERHAUL.md` with complete audit
2. Plan for Phase 1 spike (ragdoll sync approach A vs C)
3. Stop for user approval before proceeding to Phase 1

I recommend we start with fixing the critical bugs identified above before proceeding with the full audit, as these may affect the accuracy of our Phase 0 findings.