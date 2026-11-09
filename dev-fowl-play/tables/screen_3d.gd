class_name Screen3D
extends Node3D

const GLASS_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_back;

uniform float line_count = 70.0;
uniform float line_strength = 0.22;
uniform float vignette_strength = 0.35;
uniform float glass_alpha = 0.05;
uniform vec4 tint : source_color = vec4(0.55, 0.8, 1.0, 1.0);

void fragment() {
	float scan = (0.5 + 0.5 * sin(UV.y * line_count * 6.28318)) * line_strength;
	float vig = smoothstep(0.3, 0.75, length(UV - vec2(0.5))) * vignette_strength;
	ALBEDO = tint.rgb * 0.1;
	ALPHA = clamp(glass_alpha + scan + vig, 0.0, 0.85);
}
"""

@export var panel_size := Vector2(0.8, 0.4)
@export var text_color := Color(1.0, 0.25, 0.25)
@export var big_font_size := 72
@export var caption_font_size := 28
@export var glass := true

@onready var backing: MeshInstance3D = $Backing
@onready var caption: Label3D = $Caption
@onready var big_text: Label3D = $BigText

func _ready() -> void:
	var box := BoxMesh.new()
	box.size = Vector3(panel_size.x, panel_size.y, 0.03)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.04, 0.06)
	box.material = mat
	backing.mesh = box
	if Style.font:
		caption.font = Style.font
		big_text.font = Style.font
	caption.font_size = caption_font_size
	caption.outline_size = 2
	caption.position = Vector3(0, panel_size.y * 0.3, 0.02)
	big_text.font_size = big_font_size
	big_text.outline_size = 4
	big_text.modulate = text_color
	big_text.position = Vector3(0, -panel_size.y * 0.12, 0.02)
	if glass:
		_add_glass()

func _add_glass() -> void:
	var shader := Shader.new()
	shader.code = GLASS_CODE
	var gm := ShaderMaterial.new()
	gm.shader = shader
	gm.render_priority = 2
	var quad := QuadMesh.new()
	quad.size = panel_size
	quad.material = gm
	var g := MeshInstance3D.new()
	g.mesh = quad
	g.position = Vector3(0, 0, 0.035)
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(g)

func set_text(big: String, small: String = "") -> void:
	big_text.text = big
	caption.text = small
	var fit := int(panel_size.x * 0.9 / (maxi(big.length(), 1) * 0.55 * big_text.pixel_size))
	big_text.font_size = mini(big_font_size, fit)

func set_color(c: Color) -> void:
	big_text.modulate = c
