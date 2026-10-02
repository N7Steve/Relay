# Relay

Relay es una aplicación independiente de finanzas personales que evoluciona
nuestro fork de [Sure](https://github.com/N7Steve/sure), basado en
[Sure Finance](https://github.com/we-promise/sure) y
[Maybe Finance](https://github.com/maybe-finance/maybe).

Sus prioridades son la exactitud de los datos, Agenda, las previsiones, los
informes y una visión comprensible de los compromisos y la liquidez futura.
Las mejoras de upstream se evalúan e incorporan de forma selectiva.

## Estado de la separación

El historial se conserva íntegro. La primera entrega introduce el nombre Relay
en la marca web y los textos traducidos. Los nombres técnicos, la versión,
los logos y los clientes heredados se migrarán por fases.

El plan, el inventario de referencias, los riesgos de compatibilidad y los
criterios de validación están en [RELAY_MIGRATION.md](RELAY_MIGRATION.md).
Las decisiones del producto están en [FORK_EVOLUTION.md](FORK_EVOLUTION.md) y el
mapa de funciones propias en [FORK_CUSTOMIZATIONS.md](FORK_CUSTOMIZATIONS.md).

## Desarrollo y validación

- [Guías de desarrollo](docs/llm-guides/README.md).
- [Arquitectura](docs/llm-guides/architecture.md).
- [Pruebas en Docker desde Windows](docs/llm-guides/docker-tests.md).
- [Aplicación local con Docker](docs/llm-guides/docker-local-app.md).
- [Contribuciones](CONTRIBUTING.md) y [convenciones del repositorio](AGENTS.md).

Los scripts locales conservan todavía nombres de proyecto `sure-local` y
`sure-tests`. Antes de arrancar Relay junto a Sure, aislar proyectos y puertos
como describe el plan. Las pruebas de esta entrega usan `relay-tests` mediante
Compose explícitamente.

## Instalación y clientes

Las [guías de hosting](docs/hosting/docker.md) y el
[inventario de clientes](docs/clients.md) se conservan como referencia heredada.
Sus imágenes, dominios, callbacks y canales de distribución aún pueden apuntar
a Sure. Consultar el plan antes de utilizarlos para desplegar Relay.

La primera publicación del código no publica imágenes ni lanza una nueva
versión móvil o de escritorio. Relay ejecuta CI en su rama `main`.

## Procedencia y licencia

Relay conserva la [licencia AGPLv3](LICENSE), el historial y las atribuciones
heredadas. Es un proyecto independiente, sin afiliación ni respaldo de
Maybe Finance Inc. ni del equipo de Sure Finance.
