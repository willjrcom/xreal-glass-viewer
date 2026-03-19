# PrismaXR

Multi-monitor virtual workspace para óculos XREAL Air 2. Transforma um único Mac em um setup de até 3 telas espaciais visíveis nos óculos.

## Funcionalidades

- **1, 2 ou 3 telas virtuais** — selecionável pelo painel de controle
- **Captura via ScreenCaptureKit** — captura o display principal ou janelas individuais
- **Renderização Metal** — 3 planos texturizados em espaço 3D com layout configurável
- **Detecção automática de XREAL** — abre janela fullscreen nos óculos quando conectados; fecha ao desconectar
- **Painel de controle** — selecionar fonte (display/app), ajustar posição e distância de cada tela
- **Presets** — Foco (1 tela), Pesquisa (2 telas), Apresentação (3 telas)
- **Exclusão inteligente** — filtra janelas do sistema e o próprio PrismaXR da captura

## Requisitos

- macOS 12.3+ (Apple Silicon)
- XREAL Air 2 conectado via USB-C/DisplayPort

## Estrutura

```
Sources/
  PrismaXRApp/              # AppDelegate, ControlPanelView, LayoutViewModel
  PrismaXRCapture/          # CaptureService (ScreenCaptureKit)
  PrismaXRRenderer/         # Renderer (Metal), Shaders, DeskLayoutConfiguration
  PrismaXRTracking/         # HeadTrackingService (CoreMotion)
  PrismaXRLayout/           # LayoutController (Spaces awareness)
  PrismaXRVirtualDisplay/   # VirtualDisplayManager (CGVirtualDisplay, experimental)
```

## Como usar

```bash
swift build && swift run PrismaXR
```

1. Conecte os XREAL Air 2 — o app detecta automaticamente e abre em fullscreen nos óculos
2. Use o **Controle PrismaXR** (painel flutuante) para:
   - Selecionar quantidade de telas (1, 2 ou 3)
   - Escolher a fonte de cada mesa (Desktop ou app específico)
   - Ajustar posição horizontal e distância
3. `⌘Q` para fechar

## Painel de Controle

| Controle | Descrição |
|----------|-----------|
| Quantidade de Telas | Segmented picker: 1, 2 ou 3 |
| Fonte | Picker por mesa: Desktop (display) ou app (janela) |
| Posição | Slider horizontal (-1.5m a +1.5m) |
| Distância | Slider de profundidade (0.3m a 3.5m) |

## Próximos Passos

1. **NRSDK** — integrar head tracking 6DoF real dos óculos
2. **Displays virtuais** — CGVirtualDisplay para monitores interativos reais (experimental)
3. **Persistência** — salvar/restaurar layouts customizados
4. **Gestos** — atalhos de teclado e trackpad para trocar telas
