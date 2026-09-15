extends ball

func tick_physics(state:State,delta:float) -> void:
	super(state,delta)

	if not Master:Game.free_node(self)
