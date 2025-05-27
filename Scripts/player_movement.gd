extends CharacterBody2D

@export var speed = 100.0       # Velocidad de movimiento del personaje
@export var acceleration = 50.0  # Qué tan rápido alcanza la velocidad máxima
@export var deceleration = 50.0  # Qué tan rápido se detiene
@export var arrival_distance = 10.0  # Distancia a la que se considera que llegó al destino

var target_position = null  # Posición objetivo donde se moverá el personaje
var screen_size           # Tamaño de la pantalla (inicializado en _ready)
var is_selected = false   # Indica si esta unidad está seleccionada

# Variables para animación
var animated_sprite: AnimatedSprite2D
var current_direction = Vector2.ZERO  # Dirección actual del movimiento
var last_direction = Vector2.DOWN     # Última dirección válida (para idle)
var is_moving = false                 # Si la unidad se está moviendo

# Enum para las 8 direcciones
enum Direction {
	SOUTH,     # S  - Abajo
	SOUTHEAST, # SE - Abajo-Derecha
	EAST,      # E  - Derecha
	NORTHEAST, # NE - Arriba-Derecha
	NORTH,     # N  - Arriba
	NORTHWEST, # NW - Arriba-Izquierda
	WEST,      # W  - Izquierda
	SOUTHWEST  # SW - Abajo-Izquierda
}

# Nombres de las animaciones (ajusta estos nombres según tus animaciones en SpriteFrames)
var animation_names = {
	Direction.SOUTH: {"run": "run_south", "idle": "idle_south"},
	Direction.SOUTHEAST: {"run": "run_southeast", "idle": "idle_southeast"},
	Direction.EAST: {"run": "run_east", "idle": "idle_east"},
	Direction.NORTHEAST: {"run": "run_northeast", "idle": "idle_northeast"},
	Direction.NORTH: {"run": "run_north", "idle": "idle_north"},
	Direction.NORTHWEST: {"run": "run_northwest", "idle": "idle_northwest"},
	Direction.WEST: {"run": "run_west", "idle": "idle_west"},
	Direction.SOUTHWEST: {"run": "run_southwest", "idle": "idle_southwest"}
}

# Señales para comunicarse con otros nodos
signal unit_selected(unit)             # Emitida cuando esta unidad es seleccionada
signal unit_reached_destination(unit)  # Emitida cuando la unidad llega a su destino

func _ready():
	# Obtener el tamaño de la pantalla para limitar el movimiento si es necesario
	screen_size = get_viewport_rect().size
	# Buscar el AnimatedSprite2D
	animated_sprite = find_child("AnimatedSprite2D")
	if not animated_sprite:
		print("AVISO: No se encontró AnimatedSprite2D en ", name)
	# Establecer un área de colisión si no existe
	if not has_node("SelectionArea"):
		print("AVISO: Esta unidad no tiene un nodo 'SelectionArea'. Es recomendado añadir un Area2D con este nombre.")
	# Iniciar sin selección visual
	update_selection_visual(false)
	# Iniciar con animación idle hacia abajo
	play_animation_for_direction(last_direction, false)

# Función que se ejecuta cada frame para el movimiento físico
func _physics_process(delta):
	var was_moving = is_moving
	# Si tenemos un objetivo, movemos el personaje hacia él
	if target_position:
		# Calcular dirección y distancia al objetivo
		var direction = target_position - global_position
		var distance = direction.length()
		# Si ya llegamos suficientemente cerca del objetivo, detenemos al personaje
		if distance < arrival_distance:
			# Desacelerar hasta detenerse
			velocity = velocity.move_toward(Vector2.ZERO, deceleration)
			var old_target = target_position
			target_position = null  # Limpiar el objetivo
			is_moving = false
			# Notificar que hemos llegado al destino
			emit_signal("unit_reached_destination", self)
		else:
			# Normalizar la dirección y aplicar aceleración gradualmente
			direction = direction.normalized()
			velocity = velocity.move_toward(direction * speed, acceleration)
			current_direction = direction
			is_moving = true
	else:
		# Si no hay objetivo, desacelerar hasta detenerse completamente
		velocity = velocity.move_toward(Vector2.ZERO, deceleration)
		is_moving = velocity.length() > 1.0  # Considera que se está moviendo si la velocidad es > 1
	# Aplicar el movimiento calculado usando el motor de física
	move_and_slide()
	# Actualizar animaciones solo si el estado de movimiento cambió
	if was_moving != is_moving or (is_moving and current_direction.length() > 0):
		update_animation()

# Actualizar la animación basada en la dirección del movimiento
func update_animation():
	if is_moving and current_direction.length() > 0:
		# Si se está moviendo, usar la dirección actual
		last_direction = current_direction
		play_animation_for_direction(current_direction, true)
	else:
		# Si está parado, usar la última dirección válida para idle
		play_animation_for_direction(last_direction, false)

# Reproducir la animación apropiada para una dirección dada
func play_animation_for_direction(direction: Vector2, running: bool):
	if not animated_sprite:
		return
	var dir_enum = vector_to_direction_enum(direction)
	var anim_type = "run" if running else "idle"
	var animation_name = animation_names[dir_enum][anim_type]
	# Verificar si la animación existe en el SpriteFrames
	if not animated_sprite.sprite_frames.has_animation(animation_name):
		print("AVISO: La animación '", animation_name, "' no existe en SpriteFrames")
		return
	# Solo cambiar animación si es diferente a la actual
	if animated_sprite.animation != animation_name:
		animated_sprite.play(animation_name)

# Convertir un Vector2 de dirección a uno de los 8 enum de dirección
func vector_to_direction_enum(direction: Vector2) -> Direction:
	# Normalizar la dirección
	var normalized_dir = direction.normalized()
	# Calcular el ángulo en radianes
	var angle = atan2(normalized_dir.y, normalized_dir.x)
	# Convertir a grados y normalizar a 0-360
	var degrees = rad_to_deg(angle)
	if degrees < 0:
		degrees += 360
	# Determinar la dirección basada en el ángulo
	# Dividimos en 8 sectores de 45 grados cada uno
	if degrees >= 337.5 or degrees < 22.5:
		return Direction.EAST      # 0° (derecha)
	elif degrees >= 22.5 and degrees < 67.5:
		return Direction.SOUTHEAST # 45° (abajo-derecha)
	elif degrees >= 67.5 and degrees < 112.5:
		return Direction.SOUTH     # 90° (abajo)
	elif degrees >= 112.5 and degrees < 157.5:
		return Direction.SOUTHWEST # 135° (abajo-izquierda)
	elif degrees >= 157.5 and degrees < 202.5:
		return Direction.WEST      # 180° (izquierda)
	elif degrees >= 202.5 and degrees < 247.5:
		return Direction.NORTHWEST # 225° (arriba-izquierda)
	elif degrees >= 247.5 and degrees < 292.5:
		return Direction.NORTH     # 270° (arriba)
	else: # degrees >= 292.5 and degrees < 337.5
		return Direction.NORTHEAST # 315° (arriba-derecha)

# Función para seleccionar esta unidad
# Llamada cuando el jugador selecciona esta unidad
func select():
	is_selected = true
	update_selection_visual(true)
	emit_signal("unit_selected", self)  # Notificar que esta unidad fue seleccionada
	print("Unidad seleccionada: ", name)

# Función para deseleccionar esta unidad
# Llamada cuando el jugador selecciona otra unidad o hace click fuera
func deselect():
	is_selected = false
	update_selection_visual(false)
	print("Unidad deseleccionada: ", name)

# Actualizar el visual de selección
# Cambia la apariencia de la unidad para indicar si está seleccionada o no
func update_selection_visual(selected):
	# Modificar el sprite principal para destacar si está seleccionado
	if has_node("Sprite2D"):
		if selected:
			get_node("Sprite2D").modulate = Color(1.2, 1.2, 1.2)  # Más brillante cuando seleccionado
		else:
			get_node("Sprite2D").modulate = Color(1, 1, 1)  # Color normal
	
	# Si hay un nodo específico para indicar selección, mostrarlo u ocultarlo
	if has_node("SelectionIndicator"):
		get_node("SelectionIndicator").visible = selected

# Establecer destino para la unidad
# Solo mueve la unidad si está seleccionada
func set_move_target(pos):
	if is_selected:
		target_position = pos
		print("Estableciendo destino para ", name, " en ", target_position)

# Comprobar si esta unidad contiene el punto (para detección de toques)
# Esta función es CRUCIAL para la correcta selección de unidades
func contains_point(point):
	# Primero comprobamos si el punto está dentro del área de selección
	if has_node("SelectionArea") and get_node("SelectionArea") is Area2D:
		var area = get_node("SelectionArea")
		# Convertir el punto global a coordenadas locales del área. Esto es 
		# crítico: debemos transformar las coordenadas del mundo a coordenadas 
		#locales para que la detección de colisión funcione correctamente con el
		# zoom y la posición de la cámara
		var local_point = area.to_local(point)
		# Obtener la forma de colisión y verificar si el punto está dentro
		var collision_shape = area.get_node("CollisionShape2D")
		if collision_shape and collision_shape.shape:
			var shape = collision_shape.shape
			
			if shape is RectangleShape2D:
				# Para rectángulos, verificamos si el punto está dentro de los límites del rectángulo
				var extents = shape.size / 2
				return local_point.x >= -extents.x and local_point.x <= extents.x and \
					   local_point.y >= -extents.y and local_point.y <= extents.y
			else:
				# Para otros tipos de formas, usamos un enfoque simplificado basado en la distancia
				return area.global_position.distance_to(point) < 5
	
	# Si no hay área de selección específica, fallback al shape de colisión principal
	elif has_node("CollisionShape2D"):
		var collision_shape = get_node("CollisionShape2D")
		if collision_shape and collision_shape.shape:
			var shape = collision_shape.shape
			# Convertir a coordenadas locales del cuerpo de colisión
			var local_point = to_local(point)
			
			if shape is RectangleShape2D:
				var extents = shape.size / 2
				return local_point.x >= -extents.x and local_point.x <= extents.x and \
					   local_point.y >= -extents.y and local_point.y <= extents.y
			else:
				return global_position.distance_to(point) < 5
	
	# Fallback básico si no hay formas de colisión definidas
	# Esto usa un círculo simple alrededor de la posición de la unidad
	# Aumentamos la tolerancia para mejorar la selección táctil
	return global_position.distance_to(point) < 5
