# Mural de Recados — Docker, Kubernetes e Terraform

Fork do [desafio Full Cycle](https://github.com/devfullcycle/desafio-docker-kubernetes-and-terraform).
O enunciado original está em [`docs/`](docs/arquitetura.md) (arquitetura-alvo). Este README documenta
o que foi entregue e as decisões tomadas.

## Como rodar

Requisitos: Docker, [kind](https://kind.sigs.k8s.io/), [Helm](https://helm.sh/) e
[Terraform](https://developer.hashicorp.com/terraform) (`brew install kind helm hashicorp/tap/terraform`
no macOS — o Homebrew removeu o formula de `terraform` do core por licença, por isso o tap separado).

```bash
# 1. Entender a app localmente (opcional, não faz parte da entrega em si)
docker compose up --build
open http://localhost:8080

# 2. Entrega de verdade: cluster + app via Terraform
cd infra/terraform
terraform init
terraform apply     # cria cluster kind, builda/carrega as imagens, instala Traefik, faz deploy do chart
open http://mural.localtest.me

terraform apply     # roda de novo: 0 added, 0 changed, 0 destroyed
terraform destroy   # remove tudo (cluster incluso)
```

`*.localtest.me` resolve para `127.0.0.1` por DNS público — não precisa editar `/etc/hosts`.

## O que foi entregue

- **`app/docker/api.Dockerfile`** — build multi-stage, binário Go estático (`CGO_ENABLED=0`), imagem
  final `scratch`.
- **`app/docker/web.Dockerfile`** — `nginx:1.27-alpine` servindo `app/web`, com `API_UPSTREAM`
  parametrizável via `envsubst` (mesma imagem serve compose e Kubernetes sem rebuild).
- **`infra/helm/mural/`** — chart com Deployments (api/web), StatefulSet+PVC (postgres), Services,
  Ingress, ConfigMap, Secret e o Job de migração como hook do Helm.
- **`infra/terraform/`** — providers `kind` + `kubernetes` + `helm`. Cria o cluster, builda e carrega
  as imagens, instala o Traefik e aplica o chart — um único `apply` de ponta a ponta.

## Tamanho da imagem da API: antes/depois

| Imagem | Tamanho |
|---|---|
| `golang:1.23-alpine` (dev, `go run`) | 361 MB |
| `mural-api` (multi-stage, `scratch`) | **12.2 MB** |

Redução de ~97%. O binário Go compilado estaticamente não precisa de toolchain, libc ou shell —
`scratch` só tem o executável. `mural-web` (nginx + estático) ficou em 77.3 MB.

## Decisões e porquês

**Migração como hook `post-install,post-upgrade`, não `pre-install`.**
Tentei `pre-install` primeiro (parecia mais natural: "roda antes de tudo"). Não funciona: hooks
`pre-install` executam *antes* dos recursos normais do release — Secret e Postgres StatefulSet
ainda não existem, o Job de migração falha com "secret not found". `post-install`/`post-upgrade`
rodam depois que Postgres/Secret já foram criados, mas antes de o release ser marcado como
`deployed`. A API sobe em paralelo e fica presa em not-Ready (via `/readyz`) até o hook terminar.

**`helm_release.mural` precisa de `wait = false`.**
A ordem interna do Helm num install é: aplicar os recursos → se `wait=true`, esperar eles ficarem
prontos → só depois disparar os hooks `post-install`. Como a API nunca fica `Ready` sem a migração
já ter rodado, `wait=true` trava esperando a API para sempre — e a migração (que destravaria a API)
nunca chega a executar. `wait=false` resolve: o Helm continua aguardando o Job do hook terminar
(isso é sempre bloqueante, independe da flag `wait`), só não fica esperando os pods da app ficarem
prontos depois.

**Traefik: `service.spec.type=ClusterIP`, não o default `LoadBalancer`.**
No chart oficial do Traefik a chave certa é `service.spec.type` (não `service.type` — só descobri
rodando `helm show values` e comparando com o Service real no cluster). Deixado no default
(`LoadBalancer`), o `kind` nunca atribui IP externo e o `--wait` do Helm trava até o timeout.
Como o roteamento chega ao Traefik via `hostPort` 80/443 (mapeado pelo `kind` para o host), não
precisa de LoadBalancer — `ClusterIP` resolve e o install completa em segundos.

**Rebuild/reload de imagem só quando o código muda.**
O Terraform builda e carrega as imagens via `null_resource` com `triggers` baseados em hash
(`filesha1`) do código-fonte e do Dockerfile. Isso é o que garante o "apply 2x → 0 changed": sem
mudança de conteúdo, o `local-exec` de build/`kind load` nem roda de novo.

**Credencial do banco.** `DATABASE_URL` (com a senha embutida) vive só no `Secret` do chart,
nunca em texto plano em Deployment/ConfigMap. O valor em si é parametrizável via `values.yaml`/
`--set` do Terraform (`postgres.password`), como o desafio pede — em produção isso viria de
`TF_VAR_postgres_password` ou de um `.tfvars` fora do controle de versão, não do default do
repositório.

**Probes.** `/healthz` (liveness) nunca toca no banco — só confirma que o processo está de pé.
`/readyz` (readiness) checa a tabela `messages`. Ligar a liveness em `/readyz` mataria o pod em
CrashLoop enquanto a migração ainda não rodou; por isso a separação estrita entre as duas probes
no `Deployment` da API.

## Estrutura

```
app/docker/          Dockerfiles (api.Dockerfile, web.Dockerfile)
infra/helm/mural/     chart Helm (Deployments, StatefulSet+PVC, Ingress, Secret, ConfigMap, Job hook)
infra/terraform/      main.tf / variables.tf / outputs.tf / versions.tf
docker-compose.yml    stack local com imagens oficiais, só para entender a app
docs/arquitetura.md   arquitetura-alvo (enunciado original)
```

## Bônus

Não implementado (HPA/load test e Makefile ficaram fora do escopo desta entrega).
