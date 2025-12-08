# LapseForge

LapseForge es una aplicación nativa en SwiftUI para crear increíbles videos timelapse en iOS. Permite importar videos o capturar imágenes directamente desde la cámara, gestionando la duración y composición de las secuencias a tu gusto.

## Características principales

- **Captura desde cámara**: Toma imágenes periódicamente para generar tus timelapse, eligiendo cada cuanto quieres tomarlas.
- **Importación de videos**: Convierte videos de la galería en secuencias dentro de tu proyecto.
- **Gestión de secuencias**: Un mismo video puede tener varias secuencias, asignándoles la duración deseada.
- **Interfaz nativa**: 100% SwiftUI.

## Instalación y enlaces
LapseForge está disponible en su versión Beta en [TestFlight](https://testflight.apple.com/join/d1d4GbyH "TestFlight").

Por ahora, LapseForge no está disponible en la App Store. Próximamente aquí se añadirán el enlace de la store.

## Hoja de ruta (Roadmap)

### Versión 1.0
- [X] Permitir ajustar el intervalo entre capturas de la cámara (no solo cada 1s) **[Prioridad Alta]**
- [X] Exportación de video final desde las secuencias creadas **[Prioridad Alta]**
- [X] Reproducción in app
- [X] Eliminar la dependencia privada de DeveloperKit para poder hacer el proyecto Open Source
- [X] Crear los workflow de Xcode Cloud
- [X] Liberación automática de archivos y recursos cuando se elimina una secuencia o proyecto
- [X] Icono
- [X] Traducción a otros idiomas (por ejemplo, inglés)
- [X] Publicar la app en App Store

### Versión 1.1
- [X] Mejoras de interfaz y experiencia de usuario
  - Selector de resolución ✅
  - Zoom ✅
  - Flash ✅
  - ~~Apagar pantalla durante la captura~~
  - Soporte dirección al capturar ✅
  - ~~Onion Skin~~
- [X] Gestión desde Apple Watch: iniciar/detener capturas remotamente

### Versión 1.2
- [ ] Soporte para edición básica de las secuencias (recortar, reordenar, cambiar duración)

### Versión 1.3
- [ ] Posibilidad de añadir música o audio a los timelapse exportados

### Sugerencias futuras
- Integración con iCloud para sincronización de proyectos
- Notificaciones cuando termine una captura o exportación.
- Soporte para atajos de Siri (pensar cómo).
- Guardar/exportar directamente a álbumes específicos de la galería.
- Analítica o estadísticas de uso.

## Contribuciones
Este es un proyecto abierto y colaborativo.  
Cualquier persona puede proponer mejoras o nuevas funcionalidades mediante un **Pull Request**.  

#### **Nota sobre builds y pruebas:**
- Debido a las limitaciones de Xcode Cloud, cuando se crea o modifica un pull request se generará automáticamente una **build interna**. Esta build deberá ser aprobada antes de generar la **build externa** disponible en [TestFlight](https://testflight.apple.com/join/d1d4GbyH) para testers externos.  
- Si quieres recibir las builds internas directamente para pruebas, ponte en contacto con el mantenedor del proyecto para ser incluido en la lista de **testers internos**.  

Cada PR aprobado generará automáticamente una nueva versión disponible en **TestFlight** para pruebas externas, una vez que la build interna haya sido aprobada.

## Licencia
Este proyecto se distribuye bajo la licencia **MIT**.  
Consulta el archivo [LICENSE](./LICENSE) para más detalles.
