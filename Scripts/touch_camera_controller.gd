extends Camera2D

# Declare variables for zoom, pan and rotate speed
@export var zoom_speed: float = 0.1  # Controla la velocidad del zoom
@export var pan_speed: float = 1.0   # Controla la velocidad del paneo
#@export var rotate_speed: float = 1.0  # Controla la velocidad de rotación (no implementado)
# These variables control camera behaviour in order to use this scene accordingly 
@export var can_pan: bool = false    # Habilita/deshabilita el paneo
@export var can_zoom: bool = false   # Habilita/deshabilita el zoom
#@export var can_rotate: bool = false # Habilita/deshabilita la rotación (no implementado)

# Variables para la diferenciación entre tap y drag
@export var tap_time_threshold: float = 0.2  # Tiempo máximo para considerar un toque como tap (en segundos)
@export var drag_distance_threshold: float = 15.0  # Distancia mínima para considerar un arrastre como drag

# Dictionary for keeping track of touch points
# La clave es el índice del toque, el valor es la posición Vector2
var touch_points: Dictionary = {}
# Seguimiento de tiempo de inicio de toques para diferenciar tap/drag
var touch_start_times: Dictionary = {}
# Seguimiento de posiciones iniciales de toque
var touch_start_positions: Dictionary = {}
# Indica si un toque está considerado como drag
var touch_is_dragging: Dictionary = {}

# Variables para el zoom
var start_distance  # Distancia inicial entre dos dedos para el zoom
var start_zoom      # Valor de zoom inicial cuando comienza el gesto

# Estado de la interacción - para diferenciar entre paneo y control de unidades
# NONE: Sin interacción activa
# PAN: Modo de paneo/zoom de cámara
# UNIT_CONTROL: Modo de selección/movimiento de unidades
# POTENTIAL_TAP: Posible tap (esperando para determinar si es tap o drag)
enum InteractionState { NONE, PAN, UNIT_CONTROL, POTENTIAL_TAP }
var current_interaction = InteractionState.NONE

# Reference for the selected unit
var selected_unit = null  # Referencia a la unidad actualmente seleccionada
# Units array
var units = []  # Almacena todas las unidades disponibles en el juego

# Punto potencial para mover una unidad (se usa después de confirmar un tap)
var potential_move_target = null
# Unidad potencial para seleccionar (se usa después de confirmar un tap)
var potential_unit_to_select = null

func _ready():
	# Encontrar todas las unidades en la escena - lo diferimos para
	# asegurarnos de que la escena esté completamente cargada
	call_deferred("gather_units")

# Buscar todas las unidades en la escena y conectar señales
# Esta función se llama después de que la escena se ha cargado completamente
func gather_units():
	# Esperar un frame para asegurar que todo está inicializado
	await get_tree().process_frame
	await get_tree().process_frame  # Un frame adicional para mayor seguridad
	# Buscar todas las unidades en la escena que pertenecen al grupo "units"
	var potential_units = get_tree().get_nodes_in_group("units")
	if potential_units.size() == 0:
		print("ADVERTENCIA: No se encontraron unidades en el grupo 'units'. Buscando CharacterBody2D.")
		# Fallback: buscar todos los CharacterBody2D si no hay grupo definido
		potential_units = get_tree().get_nodes_in_group("CharacterBody2D")
	# Filtrar solo las unidades válidas (que tengan los métodos necesarios)
	for unit in potential_units:
		if unit.has_method("select") and unit.has_method("deselect"):
			units.append(unit)
			# Conectar la señal de selección - cuando una unidad se selecciona, se notifica al controlador
			if unit.has_signal("unit_selected"):
				unit.connect("unit_selected", Callable(self, "_on_unit_selected"))
			# Conectar la señal cuando una unidad llega a su destino
			if unit.has_signal("unit_reached_destination"):
				unit.connect("unit_reached_destination", Callable(self, "_on_unit_reached_destination"))
	print("Unidades encontradas: ", units.size())

# Detect touches on the screen - función principal para manejar entrada táctil
func _input(event: InputEvent) -> void:
	# Touch start - cuando el dedo toca la pantalla
	if event is InputEventScreenTouch:
		if event.pressed:
			# Nuevo toque iniciado - el dedo toca la pantalla
			handle_touch_press(event)
		else:
			# Toque liberado - el dedo se levanta de la pantalla
			handle_touch_release(event)
	# Touch drag - cuando el dedo se mueve sobre la pantalla
	elif event is InputEventScreenDrag:
		handle_drag(event)

# Se llama cada frame para verificar tiempos de toques y confirmar taps,así como 
# la aplicación de inercia a la cámara
func _process(delta):
	# Verificar si hay toques potenciales que hayan superado el umbral de tiempo
	# para ser considerados como taps
	var current_time = Time.get_ticks_msec() / 1000.0  # Convertir a segundos
	# Crear una copia de las claves para evitar modificar el diccionario durante la iteración
	var touch_indices = touch_start_times.keys()
	for touch_index in touch_indices:
		# Verificar solo los toques que no han sido clasificados como drags
		if touch_is_dragging.has(touch_index) and touch_is_dragging[touch_index]:
			continue
		# Calcular cuánto tiempo ha pasado desde que comenzó el toque
		var elapsed_time = current_time - touch_start_times[touch_index]
		# Si ha pasado suficiente tiempo y estamos en estado POTENTIAL_TAP,
		# confirmar que es un tap y ejecutar la acción correspondiente
		if elapsed_time >= tap_time_threshold and current_interaction == InteractionState.POTENTIAL_TAP:
			# Confirmar tap - ejecutar acción de movimiento o selección
			confirm_tap()
			# Limpiar datos del toque ya procesado
			touch_start_times.erase(touch_index)
			# Cambiar el estado de interacción
			current_interaction = InteractionState.UNIT_CONTROL

# Manejar cuando se presiona la pantalla
# Esta función ahora solo registra el toque y lo clasifica inicialmente como un POTENTIAL_TAP
func handle_touch_press(event: InputEventScreenTouch):
	# Registrar el punto de toque en nuestro diccionario
	touch_points[event.index] = event.position
	touch_start_positions[event.index] = event.position
	touch_start_times[event.index] = Time.get_ticks_msec() / 1000.0  # Guardar tiempo en segundos
	touch_is_dragging[event.index] = false
	# Si es el primer toque (un solo dedo), verificar si tocó una unidad o mapa
	if touch_points.size() == 1:
		# Convertir las coordenadas de pantalla a coordenadas del mundo del juego
		var world_pos = screen_to_world(event.position)
		var unit_touched = get_unit_at_position(world_pos)
		# Guardar estos valores para usarlos si se confirma que es un tap
		potential_unit_to_select = unit_touched
		potential_move_target = world_pos
		# Inicialmente consideramos como un posible tap
		current_interaction = InteractionState.POTENTIAL_TAP
	# Si hay dos toques (dos dedos), entramos directamente en modo PAN/ZOOM
	elif touch_points.size() == 2:
		var touch_point_positions = touch_points.values()
		# Calcular la distancia inicial entre los dos dedos
		start_distance = touch_point_positions[0].distance_to(touch_point_positions[1])
		start_zoom = zoom  # Guardar el zoom actual antes de empezar el gesto
		current_interaction = InteractionState.PAN  # Entrar en modo paneo/zoom

# Confirma un tap y ejecuta la acción correspondiente (seleccionar o mover unidad)
func confirm_tap():
	if potential_unit_to_select:
		# Si tocamos una unidad, la seleccionamos
		if selected_unit != potential_unit_to_select:
			# Deseleccionar la unidad anterior si existe
			if selected_unit:
				selected_unit.deselect()
			# Seleccionar la nueva unidad
			potential_unit_to_select.select()
			selected_unit = potential_unit_to_select
	elif selected_unit and potential_move_target:
		# Si no tocamos unidad pero hay una seleccionada, la movemos
		selected_unit.set_move_target(potential_move_target)
	# Limpiar los valores potenciales después de usarlos
	potential_unit_to_select = null
	potential_move_target = null

# Manejar cuando se libera el toque (se levanta el dedo de la pantalla)
func handle_touch_release(event: InputEventScreenTouch):
	# Si el toque termina y estamos en modo POTENTIAL_TAP, 
	# y el toque no fue clasificado como drag, lo confirmamos como tap
	if current_interaction == InteractionState.POTENTIAL_TAP and \
	not touch_is_dragging.get(event.index, false):
		confirm_tap()
	# Eliminar todos los datos de seguimiento de este toque
	touch_points.erase(event.index)
	touch_start_times.erase(event.index)
	touch_start_positions.erase(event.index)
	touch_is_dragging.erase(event.index)
	# Si ya no hay toques activos, resetear el estado de interacción (pero mantener la inercia)
	if touch_points.size() == 0 and current_interaction != InteractionState.NONE:
		current_interaction = InteractionState.NONE

# Manejar el arrastre de toque (cuando el dedo se mueve por la pantalla)
func handle_drag(event: InputEventScreenDrag):
	# Actualizar la posición del toque en nuestro diccionario
	touch_points[event.index] = event.position
	# Verificar si este arrastre supera el umbral para ser considerado un drag
	if not touch_is_dragging.get(event.index, false):
		var start_pos = touch_start_positions.get(event.index, event.position)
		var distance = start_pos.distance_to(event.position)
		if distance >= drag_distance_threshold:
			# Este toque ahora se considera un drag
			touch_is_dragging[event.index] = true
			# Si estábamos en POTENTIAL_TAP, cambiar a PAN
			if current_interaction == InteractionState.POTENTIAL_TAP:
				current_interaction = InteractionState.PAN
	# Dependiendo del estado actual de interacción, hacemos diferentes cosas
	match current_interaction:
		InteractionState.PAN:
			# Paneo con un dedo - movimiento de la cámara
			if touch_points.size() == 1 and can_pan:
				handle_pan_with_finger(event)
			# Zoom con dos dedos
			elif touch_points.size() == 2 and can_zoom:
				handle_zoom_drag()

# Manejar el paneo con un dedo - movimiento de la cámara
func handle_pan_with_finger(event):
	# Mover la cámara en dirección contraria al movimiento del dedo
	# Se ajusta por el nivel de zoom para mantener la velocidad consistente
	if touch_points.size() == 1 and can_pan:
		# El cálculo del desplazamiento se realiza actualizando directamente 
		# la posición global, en lugar de manipular el offset
		# Esto es más consistente y funciona mejor con posiciones iniciales no-cero
		offset -= event.relative * pan_speed / zoom.x
		limit_pan(offset)  # Asegurar que no excedamos los límites de la cámara
		
# Manejar el zoom con dos dedos
# Calcula el factor de zoom basado en la distancia entre los dos dedos
func handle_zoom_drag():
	if touch_points.size() != 2:
		return
	var touch_points_positions = touch_points.values()
	# Calcular la distancia actual entre los dos dedos
	var current_dist = touch_points_positions[0].distance_to(touch_points_positions[1])
	# Calcular el factor de zoom: 
	# - Si los dedos se alejan, zoom_factor < 1 (hacer zoom in)
	# - Si los dedos se acercan, zoom_factor > 1 (hacer zoom out)
	var zoom_factor = start_distance / current_dist
	if can_zoom:
		# Aplicar el nuevo zoom
		zoom = start_zoom / zoom_factor
		limit_zoom(zoom)  # Asegurar que no excedamos los límites de zoom

# Funciones para limitar el zoom y el paneo
# Límite de zoom para no hacer zoom extremadamente cercano o lejano
func limit_zoom(new_zoom):
	zoom.x = clamp(new_zoom.x, 0.1, 10)  # Limitar entre 0.1x y 10x
	zoom.y = clamp(new_zoom.y, 0.1, 10)
	
# Limitar el paneo para no salir de los límites definidos de la cámara
func limit_pan(new_offset):
	offset.x = clamp(new_offset.x, limit_left, limit_right)
	offset.y = clamp(new_offset.y, limit_top, limit_bottom)

# Convertir posición de pantalla a coordenadas del mundo
# Esta función es CRÍTICA para la interacción correcta con las unidades
# Transforma las coordenadas de la pantalla (como eventos de toque) a las coordenadas 
# del mundo del juego, teniendo en cuenta la posición, rotación y zoom de la cámara
func screen_to_world(screen_pos):
	# Usamos la matriz de transformación inversa de la cámara para convertir correctamente
	# de coordenadas de pantalla a coordenadas de mundo
	# - get_canvas_transform() obtiene la matriz que transforma coordenadas de canvas a mundo
	# - affine_inverse() obtiene la matriz inversa (de pantalla a mundo)
	return get_canvas_transform().affine_inverse()*screen_pos

# Obtener la unidad en una posición específica
# Recorre todas las unidades y verifica si el punto está dentro de alguna
func get_unit_at_position(world_pos):
# Usar marcador de depuración visual (opcional)
	print("Comprobando posición: ", world_pos)
	# Agregar un pequeño margen de tolerancia para mejorar la selección táctil
	#var tolerance = 5.0  # Píxeles de tolerancia
	for unit in units:
		if unit.contains_point(world_pos):
			# print("Unidad encontrada en posición exacta: ", unit.name)
			return unit
	# Si no encontramos ninguna unidad con la posición exacta, 
	# probamos con una tolerancia para facilitar la selección en táctil
	#for unit in units:
		## Verificar si alguna unidad está cerca usando la tolerancia
		#if unit.global_position.distance_to(world_pos) < tolerance + 40:  # 40 es aproximadamente el tamaño de la unidad
			## print("Unidad encontrada con tolerancia: ", unit.name)
			#return unit
	# No se encontró ninguna unidad en esta posición
	return null
	
# Callback cuando una unidad es seleccionada
# Se llama cuando se emite la señal unit_selected desde una unidad
func _on_unit_selected(unit):
	# Ya no deseleccionamos la unidad aquí para evitar duplicación
	# Esto se hace en confirm_tap() cuando se selecciona una nueva unidad
	# Actualizar la referencia a la unidad seleccionada
	selected_unit = unit

# Callback cuando una unidad llega a su destino
# Se llama cuando se emite la señal unit_reached_destination desde una unidad
func _on_unit_reached_destination(unit):
	# Aquí puedes añadir lógica para cuando una unidad llega a su destino
	# Por ejemplo, reproducir un sonido, animar algo, etc.
	print("Unidad llegó a su destino: ", unit.name)
