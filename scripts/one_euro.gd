extends RefCounted

var min_cutoff: float
var beta: float
var derivative_cutoff: float
var value := 0.0
var derivative := 0.0
var primed := false


func _init(p_min_cutoff := 1.0, p_beta := 0.02, p_derivative_cutoff := 1.0) -> void:
	min_cutoff = p_min_cutoff
	beta = p_beta
	derivative_cutoff = p_derivative_cutoff


func reset(start := 0.0) -> void:
	value = start
	derivative = 0.0
	primed = true


func filter(sample: float, delta: float) -> float:
	if not primed or delta <= 0.0:
		reset(sample)
		return value
	var raw_derivative := (sample - value) / delta
	derivative = lerpf(derivative, raw_derivative, _alpha(derivative_cutoff, delta))
	var cutoff := min_cutoff + beta * absf(derivative)
	value = lerpf(value, sample, _alpha(cutoff, delta))
	return value


static func _alpha(cutoff: float, delta: float) -> float:
	var tau := 1.0 / (TAU * cutoff)
	return 1.0 / (1.0 + tau / delta)
