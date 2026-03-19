# Estado do Spatial Tracking (XREAL Air 2)

Este documento resume as descobertas técnicas feitas durante a implementação do tracking para os óculos XREAL Air 2 no macOS usando IOKit, para servir de base para futuras implementações.

## 1. Identificação do Dispositivo
- **Vendor ID**: `0x3318`
- **Product ID**: `0x0428` (Air 2) / `0x0424` (Air 1)
- **Interface IMU Crítica**:
  - No macOS, o IMU real muitas vezes reporta VID/PID `0x0/0x0` em algumas APIs.
  - **Usage Page**: `0xFF00`
  - **Usage**: `0x04`
  - **Packet Length**: 122 bytes constantes.

## 2. Estrutura do Pacote (122 bytes)
O pacote começa com o cabeçalho `0xEC`. As descobertas de mapeamento via análise de entropia e logs side-by-side indicam:

- **Offset 0**: Header (`0xEC`) / Sequenciador.
- **Offset 20, 24, 28**: Acelerômetro X, Y, Z (aparentemente `Int32` Little-Endian).
- **Offset 32, 36, 40**: **Orientação Absoluta (Euler Angles)**.
  - Formato: `Float32` Little-Endian.
  - Unidade: Graus (Degrees).
  - Um dos eixos (geralmente offset 40) reporta valores na faixa de ~30-40 graus em repouso dependendo da inclinação.

## 3. Lógica de Tracking Implementada
A implementação atual no arquivo `XrealHIDTrackingAdapter.swift` tenta usar esses ângulos absolutos para evitar drift (cair da tela):
- Converte os graus lidos nos offsets 32, 36 e 40 para radianos.
- Aplica quatérnios de rotação nos eixos correspondentes.
- O mapeamento sugerido (sujeito a validação final de eixos) é:
  - `Float32` @ 32 -> Pitch
  - `Float32` @ 36 -> Yaw
  - `Float32` @ 40 -> Roll

## 4. Logs de Movimentação
Foi capturado um dataset de calibração em `/tmp/xreal_imu_final.log` (se ainda disponível no sistema) contendo sequências de "Sim", "Não" e inclinação lateral.

## 5. Pendências
- Validar se o sistema de coordenadas (handness) bate com o Renderer.
- Confirmar se o offset de 122 bytes contém samples múltiplos ou apenas um slot de pose absoluta.

---
*Gerado para facilitar a continuidade do trabalho por outra IA ou desenvolvedor.*
