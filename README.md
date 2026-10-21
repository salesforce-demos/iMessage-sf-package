# iMessage Demo Config

A Salesforce org that stores the configuration for the iMessage demo app and
serves it as JSON from a public URL. You edit the demo in Salesforce, and the app
reads it from that URL, so you only paste the URL into the app once.

```
Salesforce records                 public Site                    iOS app
iMessage Demo  ──── Apex ────►  /imessage/DemoConfig  ──HTTPS──►  paste the URL once
```

## Requirements

- Salesforce CLI (`sf`)
- A Dev Hub org with scratch orgs enabled

## Setup

Create a scratch org, deploy the metadata and load the sample demo:

```bash
sf org create scratch -f config/project-scratch-def.json -a imessage-config \
  --target-dev-hub <your-dev-hub> --duration-days 30 --set-default
sf project deploy start --target-org imessage-config
sf org assign permset --name iMessage_Demo_Admin --target-org imessage-config
sf apex run --target-org imessage-config --file scripts/seedDemo.apex
```

The Site's guest user is created only after the Site exists, so grant it read
access in a separate step:

```bash
sf apex run --target-org imessage-config --file scripts/assignGuest.apex
```

Get the endpoint URL:

```bash
sf data query --target-org imessage-config \
  --query "SELECT Domain.Domain, PathPrefix FROM DomainSite"
```

The URL has the form `https://<domain>/<prefix>/DemoConfig`. Paste it into the
app's configuration screen.

## Using the org

### Builder tab

Open the **Builder** tab to edit a demo visually:

1. **Demo**: pick a demo or create one, and give it a config name.
2. **Conversations**: add the message threads and set each thread's key.
3. **Messages**: add the steps of each conversation and drag them into order.
4. **Notifications**: add the banners that appear during calls.
5. **Phone app**: choose the contacts shown in Favorites and their call settings.

The preview on the right updates as you type. The panel under the toolbar lists
problems that will break the demo and warnings that only look unfinished. Fix
every problem before you save.

Saving replaces the demo's conversations, messages and notifications. Use
**Refresh** after records change outside the Builder.

### Serving a demo

- Mark one demo as **Is Active**. The bare endpoint URL serves that demo.
- To keep several demos and switch between them, leave **Is Active** off and
  use `/DemoConfig?id=<Config Name>`.

### Images

Image fields have a file picker. Uploaded files are stored in Salesforce Files
and get a public URL. Files are limited to 3 MB. You can also paste a public
`https` URL. If the preview does not show an image from another host, add that
host under **Setup → CSP Trusted Sites** with **img-src** enabled.

### Editing records directly

The **iMessage Demo Config** app has tabs for each object:

| Object | Purpose |
|---|---|
| iMessage Demo | One demo: status bar, Is Active, Bubble Style |
| iMessage Conversation | A message thread and its Phone app contact |
| iMessage Message | One scripted step |
| iMessage Notification | One banner shown during a call |

The **Await Photo** field on a message from `me` pauses the script until the user
sends a photo in the app.

## Project layout

```
force-app/main/default/
├── classes/            Endpoint and Builder logic, plus tests
├── lwc/                Builder and phone preview components
├── objects/            Custom objects and fields
├── pages/              DemoConfig page, served as application/json
├── sites/              Public Site
├── permissionsets/     Admin (edit) and Guest (read-only)
└── ...
scripts/
├── seedDemo.apex       Loads the sample demo
└── assignGuest.apex    Grants the guest user read access
```
