# PrismaXR

Prototipo inicial do app PrismaXR focado em múltiplos monitores virtuais para óculos XREAL Air 2.

## Requisitos
- macOS 15.2 (26.2) ou superior em Apple Silicon
- Xcode 16 beta / Swift 6 toolchain
- Acesso ao NRSDK mais recente (não incluso no repositório)

## Estrutura
```
Package.swift
Sources/
  PrismaXRCapture/        # serviço baseado em ScreenCaptureKit
  PrismaXRRenderer/       # stub de renderização Metal
  PrismaXRTracking/       # serviço de head tracking (CoreMotion + futuramente NRSDK)
  PrismaXRLayout/         # controlador para eventos de Spaces/Mission Control
  PrismaXRApp/            # aplicativo AppKit/MetalKit para testes
```

## Rodando (preview)
```bash
cd PrismaXR
swift run PrismaXR
```

- O app abre uma janela de preview (MTKView) com três “mesas” virtuais renderizadas em Metal.
- Se um monitor identificado como XREAL/XR/Air estiver conectado, o PrismaXR cria automaticamente uma janela fullscreen dedicada naquele display (mantendo o preview principal).

## Executando com os óculos XREAL
1. Conecte os XREAL Air 2 via USB‑C/DisplayPort e confirme no `Preferências do Sistema > Monitores` que o macOS reconheceu o display.
2. Rode `swift run PrismaXR`. O app tentará localizar um `NSScreen` cujo nome contenha “XREAL”, “XR” ou “Air” e abrirá uma janela sem bordas nesse display.
3. Use a janela de preview para depurar; a janela XR ficará em tela cheia nos óculos.
4. Para fechar, encerre o processo (`⌘C` no terminal) ou `⌘Q` na janela de preview.

## NRSDK (Head Tracking)
- Baixe o NRSDK atualizado no portal de desenvolvedores da XREAL e extraia o `NRSDK.framework`.
- Coloque o framework em um diretório local (ex.: `PrismaXR/Frameworks/NRSDK.framework`) e configure o Xcode/SwiftPM para linkar assim que avançarmos para a integração real.
- Enquanto o framework não é detectado, o `HeadTrackingService` usa o `FallbackTrackingAdapter` e mantém as mesas estáticas. Ao disponibilizar o SDK, bastará expor o framework via `DYLD_FRAMEWORK_PATH` ou pelo Xcode para ativar o adaptador real (`NRSDKTrackingAdapter`).


## Próximos Passos
1. Ligar o NRSDK real para alimentar pose 6DoF nos óculos.
2. Habilitar seleção de janelas/Spaces por mesa e salvar presets locais.
3. Adicionar controles de Mission Control dentro do XR (mostrar/ocultar mesas, panic mode).

## Backlog Detalhado
1. **NRSDK completo**
   - Adicionar o `NRSDK.framework` ao projeto, expor opções de calibração no painel e garantir fallback seguro quando o SDK não estiver presente.
2. **Captura por mesa**
   - Permitir selecionar uma janela ou Space para cada card (Pesquisa/Docs/Comms) e manter múltiplos `SCStream` simultâneos.
   - Tratar casos em que a janela some (reabrir seletor, modo phantom).
3. **Modo Panorama real**
   - Transição animada entre foco e panorama (alterar offsets/radius automaticamente) e bloquear input para evitar colisão com Mission Control nativo.
4. **Persistência**
   - Salvar presets customizados/em uso no `Application Support` e restaurar na inicialização.
5. **Gestos e Panic mode**
   - Mapear atalhos de teclado/trackpad, expor toggle “Retornar ao monitor único” e HUD dentro dos óculos.
6. **UI de fontes**
   - Expandir o painel para mostrar lista de janelas com miniaturas, incluir estado de conexão dos óculos, erro de captura e logs básicos.
7. **Testes/observabilidade**
   - Adicionar telemetria leve (MetricKit), logs persistentes e testes unitários para o LayoutViewModel/renderizador.
