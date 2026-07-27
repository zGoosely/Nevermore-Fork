# SoftShutdown

Recreation of Nevermore Engine's soft shutdown service for restarting Roblox servers on update without losing players.

## Overview

- **SoftShutdownService**: Server service registered on `BindToClose`. Teleports connected players to a temporary reserved server (lobby) during server shutdown, then redirects them back into updated servers once available.
- **SoftShutdownServiceClient**: Client service that monitors soft shutdown state and displays custom UI overlay during restarting and lobby transitions.
- **SoftShutdownUI**: Custom screen overlay with blur and progress animation.
- **SoftShutdownTranslator**: Localized title and subtitle messages for update stages.
- **SoftShutdownConstants**: Attribute key definitions.
