# UNI2 Rank Wars (Standalone Lua Add-on)

Add-on oficial do **Rank Wars** para o **UNI2 Improvement Mod** (`UNI2-IM\Addons\RankWars`).

## Recursos

- Leitura de links do Rank Wars (`create`, `join`, `replay`) via linha de comando e Steam launch query.
- Criação automática de sala Player Match (limite de 2 jogadores + rematch conforme `first_to`) e entrada automática do convidado.
- Captura de resultados e envio automático dos replays `.rep` para a API do Rank Wars com retry exponencial.
- Placar ao vivo em pips direto no HUD da batalha (`src/presentation/hud.lua`).
- Janela in-game no menu F1 (`Mod -> Rank Wars`), toasts de notificação, Steam Rich Presence, Replay Viewer e modo Sandbox de teste.

## Arquitetura

```text
main.lua                 Entry point mínimo (chama src/app/bootstrap.lua)
src/
  core/                  Primitivas puras e reutilizáveis (class, cooldown, state_machine)
  domain/                Regras de negócio e contratos sem acoplamento com uni2.*
  infra/                 Adaptadores HTTP, Steam, memória e automação de sala
  app/                   Casos de uso (session, replay_viewer) e composition root (bootstrap)
  presentation/          HUD D3D9 e janela ImGui
tests/
  support/               Runner, FakeEnv isolado e spies
  unit/<camada>/         Specs unitários espelhando src/
  integration/           Testes ponta a ponta do bootstrap/main.lua
```

## Instalação

### Pelo UNI2 Mod Loader (recomendado)
1. Abra o `UNI2ModLoader.exe` na pasta do jogo.
2. Na aba **ADD-ONS**, cole a URL deste repositório no campo de link na parte inferior e clique em **DOWNLOAD & INSTALL** (ou baixe o `.zip` em Releases e clique em **INSTALL ZIP / BUNDLE**).
3. Mantenha **Rank Wars** ativado e clique em **PLAY UNI2 (STEAM)**.

Para atualizar depois, basta clicar em **UPDATE LINKED** no `UNI2ModLoader.exe` (ou ativar a checagem automática no startup na aba **CORE BASE**).

### Instalação Manual
Extraia os arquivos (`addon.ini` e `main.lua`) para:
```text
<Pasta do UNI2>\UNI2-IM\Addons\RankWars\
```

Para empacotar localmente:
```powershell
.\package.ps1
```
