class_name FocusHighlight
extends RefCounted
## A local overlay: never changes a shared mesh's original materials.
const CODE := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back;
void fragment() {
	float rim = pow(1.0 - max(dot(normalize(NORMAL), normalize(VIEW)), 0.0), 2.0);
	ALBEDO = vec3(1.0, 0.76, 0.28);
	ALPHA = 0.13 + rim * 0.38;
}
"""
var _originals := {}
var _material: ShaderMaterial

func set_target(target: Node) -> void:
	clear()
	if target == null:
		return
	if _material == null:
		_material = ShaderMaterial.new()
		var shader := Shader.new()
		shader.code = CODE
		_material.shader = shader
	_apply(target)

func _apply(node: Node) -> void:
	if node is MeshInstance3D:
		_originals[node] = node.material_overlay
		node.material_overlay = _material
	for child in node.get_children():
		_apply(child)

func clear() -> void:
	for mesh in _originals:
		if is_instance_valid(mesh):
			mesh.material_overlay = _originals[mesh]
	_originals.clear()
