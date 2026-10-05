class_name Fx
extends RefCounted
## Spawners for short-lived visual effects. Particles use CPUParticles2D
## because GPU particles are unreliable on the web (GL Compatibility) target.

static var _light_texture: GradientTexture2D


## Soft radial falloff shared by every PointLight2D in the game.
static func light_texture() -> GradientTexture2D:
	if _light_texture == null:
		var gradient := Gradient.new()
		gradient.set_color(0, Color(1, 1, 1, 1))
		gradient.set_color(1, Color(1, 1, 1, 0))
		gradient.add_point(0.35, Color(1, 1, 1, 0.45))
		_light_texture = GradientTexture2D.new()
		_light_texture.gradient = gradient
		_light_texture.width = 128
		_light_texture.height = 128
		_light_texture.fill = GradientTexture2D.FILL_RADIAL
		_light_texture.fill_from = Vector2(0.5, 0.5)
		_light_texture.fill_to = Vector2(0.5, 0.0)
	return _light_texture


static func make_light(color: Color, scale: float, energy := 1.0) -> PointLight2D:
	var light := PointLight2D.new()
	light.texture = light_texture()
	light.color = color
	light.texture_scale = scale
	light.energy = energy
	return light


## One-shot burst of square pixels that fade out, then free themselves.
static func burst(parent: Node, pos: Vector2, color: Color, amount := 10,
		speed := 70.0, direction := Vector2.UP, spread := 180.0,
		lifetime := 0.45, gravity := 260.0, size := 2.0) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.one_shot = true
	p.amount = amount
	p.lifetime = lifetime
	p.explosiveness = 1.0
	p.randomness = 0.4
	p.lifetime_randomness = 0.4
	p.direction = direction
	p.spread = spread
	p.initial_velocity_min = speed * 0.4
	p.initial_velocity_max = speed
	p.gravity = Vector2(0, gravity)
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.scale_amount_min = size * 0.6
	p.scale_amount_max = size
	var ramp := Gradient.new()
	ramp.set_color(0, color)
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	p.position = pos
	parent.add_child(p)
	p.emitting = true
	p.finished.connect(p.queue_free)
	return p


## Fading after-image used by the dash.
static func ghost(parent: Node, pos: Vector2, size: Vector2, scale: Vector2, color: Color) -> void:
	var poly := Polygon2D.new()
	var half := size.x * 0.5
	poly.polygon = PackedVector2Array([
		Vector2(-half, -size.y), Vector2(half, -size.y), Vector2(half, 0), Vector2(-half, 0)])
	poly.color = color
	poly.position = pos
	poly.scale = scale
	poly.z_index = -1
	parent.add_child(poly)
	var tween := poly.create_tween()
	tween.tween_property(poly, "modulate:a", 0.0, 0.22).from(0.6)
	tween.tween_callback(poly.queue_free)
