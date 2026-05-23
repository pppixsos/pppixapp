# PPPIX iOS — Configuração do Projeto Xcode

## 1. Criar o projeto no Xcode

```
File → New → Project
  App
  Product Name: PPPIX
  Bundle Identifier: tech.pppix.app
  Team: (sua conta Apple Developer)
  Language: Swift
  Interface: SwiftUI
```

## 2. Targets necessários

| Target | Tipo | Bundle ID |
|--------|------|-----------|
| PPPIX | App | tech.pppix.app |
| PPPIXBlockExtension | Shield Configuration Extension | tech.pppix.app.block |
| PPPIXActivityMonitor | Device Activity Monitor Extension | tech.pppix.app.monitor |

## 3. Capabilities (aba Signing & Capabilities)

**Target: PPPIX**
- Push Notifications
- Background Modes:
  - Background fetch
  - Remote notifications
  - Background processing
- Family Controls ← Screen Time API
- Keychain Sharing

**Target: PPPIXBlockExtension**
- Family Controls

**Target: PPPIXActivityMonitor**
- Family Controls

## 4. Info.plist — adicionar as seguintes chaves

```xml
<!-- Localização -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>O PPPIX usa sua localização para enviar alertas de emergência com sua posição atual.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>O PPPIX usa sua localização para enviar alertas de emergência mesmo em segundo plano.</string>

<!-- Notificações -->
<key>UIBackgroundModes</key>
<array>
    <string>fetch</string>
    <string>remote-notification</string>
    <string>processing</string>
</array>

<!-- Background Tasks -->
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>tech.pppix.app.refresh</string>
    <string>tech.pppix.app.processing</string>
</array>

<!-- Family Controls (Screen Time) -->
<key>NSFamilyControlsUsageDescription</key>
<string>O PPPIX usa o Screen Time para proteger seus apps financeiros com senha.</string>
```

## 5. Firebase — adicionar GoogleService-Info.plist

- Arrastar o arquivo `GoogleService-Info.plist` para a raiz do projeto PPPIX
- Marcar como membro do target PPPIX (não das extensões)

## 6. Swift Package Manager — dependências

```
File → Add Package Dependencies

Firebase iOS SDK:
  https://github.com/firebase/firebase-ios-sdk
  Produtos: FirebaseCore, FirebaseMessaging, FirebaseAnalytics (opcional)
```

## 7. Estrutura de arquivos no Xcode

```
PPPIX/
├── App/
│   ├── PPPIXApp.swift
│   └── RootView.swift
├── Core/
│   ├── Network/
│   │   └── APIClient.swift
│   ├── Session/
│   │   └── SessionManager.swift
│   └── Models/
│       └── Models.swift
├── Features/
│   ├── Auth/
│   │   ├── LoginView.swift
│   │   └── RegisterView.swift
│   ├── Home/
│   │   └── HomeView.swift
│   ├── Passwords/
│   │   └── PasswordSetupView.swift
│   ├── Lock/
│   │   └── LockScreenView.swift
│   ├── Alerts/
│   │   ├── AlertsView.swift
│   │   └── AlertDetailView.swift
│   ├── Vehicles/
│   │   └── VehiclesView.swift
│   ├── Contacts/
│   │   └── ContactsView.swift
│   ├── Permissions/
│   │   └── PermissionsView.swift
│   ├── Profile/
│   │   └── ProfileView.swift
│   └── Subscription/
│       └── SubscriptionView.swift
├── Services/
│   ├── AppBlock/
│   │   ├── ScreenTimeManager.swift
│   │   └── BackgroundTaskManager.swift
│   ├── Emergency/
│   │   └── EmergencyAudioService.swift
│   └── Location/
│       └── LocationService.swift
└── Resources/
    ├── Components.swift
    ├── GoogleService-Info.plist
    └── sirene.mp3 ← copiar do projeto Android

PPPIXBlockExtension/
└── ShieldConfigurationExtension.swift

PPPIXActivityMonitor/
└── PPPIXActivityMonitor.swift
```

## 8. Extensão PPPIXBlockExtension (Shield)

Criar novo arquivo `ShieldConfigurationExtension.swift`:

```swift
import ManagedSettingsUI
import UIKit

class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .dark,
            backgroundColor: UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1),
            icon: UIImage(named: "AppIcon"),
            title: ShieldConfiguration.Label(
                text: "App Bloqueado pelo PPPIX",
                color: .white
            ),
            subtitle: ShieldConfiguration.Label(
                text: "Abra o PPPIX e use a tela de senhas",
                color: UIColor(white: 0.6, alpha: 1)
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Abrir PPPIX",
                color: .white
            ),
            primaryButtonBackgroundColor: UIColor(red: 0.2, green: 0.4, blue: 1.0, alpha: 1)
        )
    }
}
```

## 9. Extensão PPPIXActivityMonitor

Criar novo arquivo `PPPIXActivityMonitor.swift`:

```swift
import DeviceActivity

class PPPIXActivityMonitor: DeviceActivityMonitor {
    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
    }

    override func eventDidReachThreshold(
        _ event: DeviceActivityEvent.Name,
        activity: DeviceActivityName
    ) {
        super.eventDidReachThreshold(event, activity: activity)
    }
}
```

## 10. App Groups (para comunicar app ↔ extensões)

Em cada target (PPPIX, PPPIXBlockExtension, PPPIXActivityMonitor):
- Signing & Capabilities → + Capability → App Groups
- Adicionar: `group.tech.pppix.app`

Use `UserDefaults(suiteName: "group.tech.pppix.app")` para compartilhar dados entre app e extensões.
