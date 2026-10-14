# mediaremote-adapter (copia incluida)

- Origen: https://github.com/ungive/mediaremote-adapter
- Commit: 797729d9b16316dc313844476c153d7a107ca0df (10 de octubre de 2026)
- Licencia: BSD 3-Clause (ver `LICENSE`)

Copia sin modificar de `bin/`, `include/` y `src/`. El cliente de prueba
(`src/test/`) no se compila; solo se conserva porque `src/adapter/test.m`
incluye su cabecera. `Scripts/build-mediaremote-adapter.sh` compila el
framework con `clang`, sin CMake.

Usa el framework privado MediaRemote. Es la única API privada del proyecto,
aprobada expresamente para el módulo de música; ver `docs/ARCHITECTURE.md`.
Para actualizar: sustituir estos directorios por los de un commit nuevo,
anotar aquí el commit y comprobar el módulo de música.
