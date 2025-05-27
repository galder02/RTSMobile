extends Node2D

# Este script gestiona la escena principal del juego

@onready var touch_camera_controller = $TouchCameraController

func _ready():
	# Asegurarnos de que la entrada táctil esté habilitada
	DisplayServer.screen_set_keep_on(true)  # Mantener la pantalla encendida
	
	# Opcional: Configurar el juego para modo apaisado (landscape)
	# DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	
	# Verificar que estamos en un dispositivo móvil
	if OS.get_name() == "Android" or OS.get_name() == "iOS":
		print("Ejecutando en dispositivo móvil")
	else:
		print("Ejecutando en PC - Puedes hacer clic para simular toques")
		
	# Verificar que existe el UnitManager
	if not touch_camera_controller:
		push_error("¡No se encontró el nodo UnitManager! Asegúrate de añadirlo como un hijo de esta escena.")
