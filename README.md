# VeltrixUPGW

Gateway UDP standalone escrito em Go, compatível com o protocolo **BadVPN udpgw**. Clientes conectam via **TCP** e o servidor encaminha datagramas **UDP** em nome deles — útil em cenários onde o tráfego UDP precisa ser tunelado por uma conexão TCP confiável (por exemplo, atrás de proxies ou túneis SSH).

## Resumo

O VeltrixUPGW implementa o formato de frames do BadVPN udpgw (somente **IPv4**). Para cada cliente TCP aceito:

1. O servidor abre um socket UDP dedicado.
2. Recebe frames com destino IP/porta e payload UDP.
3. Envia os datagramas e devolve as respostas UDP ao cliente pelo mesmo canal TCP.

Recursos principais:

- Limites configuráveis de clientes, conexões lógicas e mapeamentos UDP.
- Expiração automática de mapeamentos inativos (TTL + reap periódico).
- Métricas **Prometheus** expostas em endpoint HTTP.
- Reinício automático opcional do listener (útil para liberar recursos em deploys longos).
- Logs estruturados via `slog` (nível debug opcional).

## Requisitos

- Go **1.22+** (para compilar a partir do código-fonte)

## Compilação

```bash
go build -o udpgw ./cmd/udpgw
```

Com versão embutida:

```bash
go build -trimpath \
  -ldflags="-s -w -X main.version=v1.0.0" \
  -o udpgw \
  ./cmd/udpgw
```

## Uso

```bash
./udpgw -listen 0.0.0.0:7400
```

Encerramento gracioso com `SIGINT` ou `SIGTERM`.

### Exemplo com opções comuns

```bash
./udpgw \
  -listen 0.0.0.0:7400 \
  -max-clients 5000 \
  -map-ttl 90s \
  -idle-timeout 2m \
  -metrics-listen 127.0.0.1:9091 \
  -debug
```

## Flags disponíveis

| Flag | Padrão | Descrição |
|------|--------|-----------|
| `-version` | — | Imprime a versão e encerra. |
| `-listen` | `0.0.0.0:7400` | Endereço TCP onde o gateway escuta conexões de clientes. |
| `-debug` | `false` | Ativa logs em nível debug. |
| `-max-frame` | `65536` (64 KiB) | Tamanho máximo de um frame (mínimo: `512` bytes). |
| `-write-chan` | `1024` | Tamanho do canal de escrita por cliente (só reduz se informado entre `1` e `1023`). |
| `-udp-bind` | *(vazio)* | IP de bind dos sockets UDP por cliente (porta efêmera). Vazio = bind padrão do SO. |
| `-udp-rbuf` | `524288` (512 KiB) | Buffer de leitura UDP (só reduz se informado abaixo do máximo). |
| `-udp-wbuf` | `524288` (512 KiB) | Buffer de escrita UDP (só reduz se informado abaixo do máximo). |
| `-map-ttl` | `90s` | Tempo de vida de um mapeamento UDP antes de expirar por inatividade. |
| `-reap-every` | `10s` | Intervalo entre varreduras que removem mapeamentos expirados. |
| `-idle-timeout` | `2m` | Timeout de inatividade da sessão TCP do cliente. |
| `-max-client-conns` | `10` | Máximo de `connID` lógicos simultâneos por cliente TCP. |
| `-max-map-entries` | `32768` | Máximo de entradas no mapa UDP por cliente. |
| `-max-clients` | `10000` | Máximo de clientes TCP conectados ao mesmo tempo. |
| `-auto-restart-interval` | desabilitado | Reinicia o listener após o intervalo (ex.: `24h`). Valores `off`, `disabled`, `0` ou `0s` desativam. Mínimo: `1m`. |
| `-auto-restart-grace` | `2s` | Tempo de espera antes do reinício automático (máximo: `1m`). |
| `-metrics-listen` | `127.0.0.1:9091` | Endereço HTTP para métricas Prometheus (`/metrics`). |

Durações aceitam o formato do Go (`90s`, `2m`, `24h`, etc.). Valores inválidos ou não positivos em campos de duração caem para o padrão correspondente (com aviso no log).

## Métricas Prometheus

Com o servidor em execução, as métricas ficam disponíveis em:

```
http://127.0.0.1:9091/metrics
```

Principais séries expostas:

| Métrica | Tipo | Descrição |
|---------|------|-----------|
| `udpgw_active_clients` | Gauge | Clientes TCP conectados no momento. |
| `udpgw_clients_total` | Counter | Total de clientes aceitos. |
| `udpgw_clients_rejected_total` | Counter | Clientes rejeitados por limite (`max-clients`). |
| `udpgw_dropped_replies_total` | Counter | Respostas UDP descartadas (backpressure ou mapeamento ausente). |
| `udpgw_read_errors_total` | Counter | Erros de leitura TCP. |
| `udpgw_udp_write_errors_total` | Counter | Erros ao enviar datagramas UDP. |
| `udpgw_panics_total` | Counter | Pânicos recuperados em goroutines do servidor. |
| `udpgw_mapping_size` | Gauge | Tamanho atual do mapa de mapeamentos. |

## Protocolo

O wire format segue o **BadVPN udpgw**: frames com prefixo de tamanho (uint16 little-endian) e payload contendo `connID`, endereço IPv4 de destino, porta e dados UDP. Respostas incluem o endereço IPv4 de origem. **IPv6 não é suportado** por este framing.

## Estrutura do repositório

```
cmd/udpgw/          # Ponto de entrada e flags CLI
internal/config/    # Defaults, validação e resolução de configuração
internal/protocol/  # Codificação/decodificação de frames BadVPN udpgw
internal/server/    # Listener TCP, métricas HTTP e ciclo de vida
internal/session/   # Sessão por cliente TCP e mapeamento UDP
internal/metrics/   # Instrumentação Prometheus
```

## Licença

Consulte os termos do repositório ou do autor do projeto.
