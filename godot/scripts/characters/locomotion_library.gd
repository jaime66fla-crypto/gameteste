extends RefCounted
## Vector2.x is right; Vector2.y is backward. Walk radius .5; run radius 1.
const PATH := "res://assets/personagens/jaime/retargeted/locomotion_library.tres"
const DIRECTIONS := {"forward":Vector2(0,-1),"forward_right":Vector2(1,-1),"right":Vector2(1,0),"backward_right":Vector2(1,1),"backward":Vector2(0,1),"backward_left":Vector2(-1,1),"left":Vector2(-1,0),"forward_left":Vector2(-1,-1)}
static func load_library() -> AnimationLibrary:
    return load(PATH) as AnimationLibrary
static func build_blend_space() -> AnimationNodeBlendSpace2D:
    var blend := AnimationNodeBlendSpace2D.new()
    blend.sync = true
    blend.max_space = Vector2(1.2, 1.2)
    var idle := AnimationNodeAnimation.new()
    idle.animation = &"idle"
    blend.add_blend_point(idle,Vector2.ZERO,-1,&"idle")
    for gait in ["walk","run"]:
        for direction in DIRECTIONS:
            var node := AnimationNodeAnimation.new()
            node.animation = StringName(gait+"_"+direction)
            blend.add_blend_point(node,DIRECTIONS[direction].normalized()*(0.5 if gait=="walk" else 1.0),-1,node.animation)
    var sprint := AnimationNodeAnimation.new()
    sprint.animation = &"sprint_forward"
    blend.add_blend_point(sprint,Vector2(0,-1.15),-1,&"sprint_forward")
    return blend
