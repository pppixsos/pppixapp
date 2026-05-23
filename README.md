# PPPIX iOS — Deploy via GitHub + Xcode Cloud

## O que você vai precisar

- [ ] Conta Apple Developer ($99/ano) — obrigatório para Xcode Cloud e TestFlight
- [ ] Conta GitHub (gratuita)
- [ ] O arquivo `GoogleService-Info.plist` (já foi gerado)
- [ ] O arquivo `sirene.mp3` (copiar do projeto Android: `app/src/main/assets/sirene.mp3`)

---

## PARTE 1 — Preparar os arquivos

### 1.1 — Baixar e extrair o ZIP

1. Baixe o ZIP `PPPIX_iOS_completo.zip`
2. Extraia em qualquer pasta do Windows, ex: `C:\PPPIX_iOS\`

### 1.2 — Adicionar os arquivos obrigatórios

Dentro da pasta extraída, coloque:

```
PPPIX_iOS_full/
  PPPIX/
    Resources/
      GoogleService-Info.plist  ← ADICIONAR AQUI (já foi gerado)
      sirene.mp3                ← COPIAR do Android (app/src/main/assets/)
```

---

## PARTE 2 — Subir no GitHub

### 2.1 — Criar repositório no GitHub

1. Acesse **github.com** → faça login
2. Clique em **"New repository"** (botão verde)
3. Preencha:
   - Repository name: `pppix-ios`
   - Visibility: **Private** (importante!)
   - NÃO marque "Initialize with README"
4. Clique **"Create repository"**

### 2.2 — Subir os arquivos

O GitHub permite subir diretamente pelo navegador:

1. Na página do repositório vazio, clique em **"uploading an existing file"**
2. Arraste **TODA a pasta `PPPIX_iOS_full`** para a área de upload
   - Ou clique em "choose your files" e selecione todos os arquivos
3. Aguarde o upload completar
4. Em "Commit changes", escreva: `Initial commit - PPPIX iOS`
5. Clique **"Commit changes"**

> ⚠️ O GitHub tem limite de 100 arquivos por upload. Se travar, use o **GitHub Desktop** (app gratuito para Windows):
> 1. Baixe em desktop.github.com
> 2. File → New Repository → escolha a pasta `PPPIX_iOS_full`
> 3. Publish repository → Private

---

## PARTE 3 — Configurar Xcode Cloud

### 3.1 — Acessar o Xcode Cloud

1. Acesse **developer.apple.com/xcode-cloud**
2. Faça login com seu Apple ID (o mesmo da conta Developer)
3. Clique em **"Get Started"**

### 3.2 — Conectar o GitHub

1. Clique em **"Grant Access"** para conectar sua conta GitHub
2. Autorize o Xcode Cloud a acessar seu repositório
3. Selecione o repositório `pppix-ios`

### 3.3 — Criar o primeiro Workflow

1. Xcode Cloud vai detectar o projeto automaticamente
2. Se pedir o arquivo `.xcodeproj`, selecione **"PPPIX"**
   - O script `ci_scripts/ci_post_clone.sh` vai gerar o `.xcodeproj` automaticamente antes de compilar
3. Configure o workflow:
   - **Name:** `TestFlight`
   - **Environment:** Xcode 15, iOS 16+
   - **Start Condition:** Manual (por enquanto)
   - **Actions:**
     - Archive → Platform: iOS → Scheme: PPPIX
   - **Post-Actions:**
     - TestFlight Internal Testing → selecione seu grupo

### 3.4 — Configurar as Capabilities (uma vez só)

Na primeira build, o Xcode Cloud vai pedir para confirmar:
- **Push Notifications** → ativar
- **Family Controls** → ativar
- **Background Modes** → ativar
- **App Groups** → `group.tech.pppix.app`

Faça isso em **developer.apple.com → Certificates, IDs & Profiles → Identifiers**:

1. Acesse developer.apple.com → **Account**
2. Certificates, IDs & Profiles → **Identifiers**
3. Clique em `tech.pppix.app`
4. Ative as capabilities:
   - ✅ Push Notifications
   - ✅ App Groups → adicione `group.tech.pppix.app`
   - ✅ Family Controls
   - ✅ Background Modes
5. Salve
6. Repita para `tech.pppix.app.block` e `tech.pppix.app.monitor`

---

## PARTE 4 — Rodar a primeira build

### 4.1 — Iniciar a build

1. No Xcode Cloud, clique em **"Start Build"**
2. Aguarde ~15-20 minutos
3. Se der erro, copie a mensagem de erro e mande para o desenvolvedor

### 4.2 — Instalar via TestFlight

1. No iPhone, baixe o app **TestFlight** (App Store)
2. Na Apple Developer, vá em **TestFlight** → selecione a build
3. Adicione seu email como testador
4. Você receberá um email com link de instalação
5. Abra o TestFlight no iPhone e instale o PPPIX

---

## Erros comuns e soluções

### "No such module 'FirebaseCore'"
→ O script `ci_post_clone.sh` instalou o XcodeGen mas o SPM não baixou as dependências.
→ Solução: No workflow do Xcode Cloud, adicione o step "Resolve Package Dependencies" antes do Archive.

### "Provisioning profile doesn't include the Family Controls entitlement"
→ Faltou ativar a capability no Apple Developer.
→ Solução: Siga o Passo 3.4 novamente.

### "Missing GoogleService-Info.plist"
→ O arquivo não foi adicionado ao repositório.
→ Solução: Adicione o `GoogleService-Info.plist` na pasta `PPPIX/Resources/` e faça commit.

### "ci_post_clone.sh: Permission denied"
→ O script não tem permissão de execução.
→ Solução: Se usar GitHub Desktop ou git no terminal Windows (Git Bash):
```bash
git update-index --chmod=+x ci_scripts/ci_post_clone.sh
git commit -m "Fix script permissions"
git push
```

---

## Estrutura final do repositório

```
pppix-ios/
├── project.yml                     ← XcodeGen config
├── .gitignore
├── ci_scripts/
│   └── ci_post_clone.sh            ← Script Xcode Cloud
├── PPPIX/
│   ├── App/
│   │   ├── PPPIXApp.swift
│   │   └── RootView.swift
│   ├── Core/
│   │   ├── Models/Models.swift
│   │   ├── Network/APIClient.swift
│   │   └── Session/SessionManager.swift
│   ├── Features/
│   │   ├── Auth/LoginView.swift
│   │   ├── Auth/RegisterView.swift
│   │   ├── Home/HomeView.swift
│   │   ├── Passwords/PasswordSetupView.swift
│   │   ├── Lock/LockScreenView.swift
│   │   ├── Alerts/AlertsView.swift
│   │   ├── Alerts/AlertDetailView.swift
│   │   ├── Vehicles/VehiclesView.swift
│   │   ├── Contacts/ContactsView.swift
│   │   ├── Permissions/PermissionsView.swift
│   │   ├── Permissions/AppListView.swift
│   │   ├── Profile/ProfileView.swift
│   │   └── Subscription/SubscriptionView.swift
│   ├── Services/
│   │   ├── AppBlock/ScreenTimeManager.swift
│   │   ├── AppBlock/BackgroundTaskManager.swift
│   │   ├── Emergency/EmergencyAudioService.swift
│   │   └── Location/LocationService.swift
│   ├── Resources/
│   │   ├── Components.swift
│   │   ├── Info.plist
│   │   ├── GoogleService-Info.plist  ← você adiciona
│   │   └── sirene.mp3                ← você adiciona
│   └── PPPIX.entitlements
├── PPPIXBlockExtension/
│   ├── ShieldConfigurationExtension.swift
│   └── PPPIXBlockExtension.entitlements
└── PPPIXActivityMonitor/
    ├── PPPIXActivityMonitor.swift
    └── PPPIXActivityMonitor.entitlements
```
