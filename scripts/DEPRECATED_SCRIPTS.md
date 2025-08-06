# Deprecated Scripts

The following scripts have been consolidated into the unified `idp.sh` script for better efficiency and simplicity:

## 🚫 Deprecated (use `./scripts/idp.sh` instead)

### Replaced by `./scripts/idp.sh setup`:
- ~~`bootstrap-platform.sh`~~ → `./scripts/idp.sh setup`
- ~~`dev-setup.sh`~~ → Functionality integrated into setup
- ~~`organizational-quick-start.sh`~~ → `./scripts/idp.sh setup`

### Replaced by `./scripts/idp.sh start`:
- ~~`start-platform.sh`~~ → `./scripts/idp.sh start`
- ~~`quick-start.sh`~~ → Now a simple wrapper to `./scripts/idp.sh start`

### Replaced by `./scripts/idp.sh build-backstage`:
- ~~`setup-backstage-external.sh`~~ → `./scripts/idp.sh build-backstage`

### Replaced by `./scripts/idp.sh status`:
- Individual service status checks → `./scripts/idp.sh status`

## ✅ Still Active Scripts

### Configuration Management:
- `config-parser.sh` - Still used by unified script
- `idp-setup-wizard.sh` - Configuration wizard (also callable via `./scripts/idp.sh config`)

### Specialized Setup:
- `setup-external-localstack.sh` - LocalStack setup (called by unified script)
- `setup-cognito-auth.sh` - AWS Cognito setup
- `apply-data-protection.sh` - Security policies
- `uninstall-idp.sh` - Platform removal

### Utilities:
- `configure-backstage-repo.sh` - Repository URL configuration
- `setup-opa.sh` - OPA policy setup
- `idp-cli-mcp.sh` - MCP integration

## 🆕 New Unified Workflow

Instead of multiple scripts, use one unified command:

```bash
# Old workflow (deprecated)
./scripts/bootstrap-platform.sh
./scripts/setup-backstage-external.sh
./scripts/quick-start.sh

# New simplified workflow
./scripts/idp.sh setup          # One-time setup
./scripts/idp.sh build-backstage # Build via IDP workflows
./scripts/idp.sh start          # Start services
```

## Migration Guide

| Old Command | New Command |
|-------------|-------------|
| `./scripts/quick-start.sh` | `./scripts/idp.sh start` |
| `./scripts/bootstrap-platform.sh` | `./scripts/idp.sh setup` |
| `./scripts/setup-backstage-external.sh` | `./scripts/idp.sh build-backstage` |
| `./scripts/start-platform.sh status` | `./scripts/idp.sh status` |
| `./scripts/start-platform.sh stop` | `./scripts/idp.sh stop` |

The deprecated scripts will be removed in a future version. Please update your workflows to use the unified `idp.sh` script.