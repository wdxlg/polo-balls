extends RefCounted
## Experimental: each object is created exactly once and used exactly once.
## Off-tree construction only; _ready, assignment, insertion and destruction remain main-thread.
var source:PackedScene
var worker:Thread = Thread.new()
var gate:Semaphore = Semaphore.new()
var mutex:Mutex = Mutex.new()
var available:Array[Node] = []
var stopping:bool = false
var capacity:int = 128
var hits:int = 0
var misses:int = 0
func start(scene:PackedScene,count:int=128) -> void:
	source = scene
	capacity = count
	# Compile and initialize script resources on the main thread before sharing.
	var warm:Node = source.instantiate()
	warm.free()
	worker.start(_fill)
	gate.post()
func _fill() -> void:
	while true:
		gate.wait()
		while true:
			mutex.lock()
			var done:bool = stopping
			var full:bool = available.size() >= capacity
			mutex.unlock()
			if done:
				return
			if full:
				break
			var node:Node = source.instantiate()
			mutex.lock()
			available.append(node)
			mutex.unlock()
func count() -> int:
	mutex.lock()
	var n:int = available.size()
	mutex.unlock()
	return n
func take() -> Node:
	mutex.lock()
	var node:Node = available.pop_back() if not available.is_empty() else null
	mutex.unlock()
	gate.post()
	if node == null:
		misses += 1
		return source.instantiate()
	hits += 1
	return node
func close() -> void:
	mutex.lock()
	stopping = true
	mutex.unlock()
	gate.post()
	if worker.is_started():
		worker.wait_to_finish()
	for node:Node in available:
		node.free()
	available.clear()
