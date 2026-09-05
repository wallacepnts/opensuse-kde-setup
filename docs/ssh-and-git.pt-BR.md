# Agente SSH do Bitwarden e git

[English](ssh-and-git.md) · **Português**

Chaves SSH guardadas no cofre, sem arquivo de chave privada no disco. Vale para terminal e para
aplicativos gráficos.

## 1. Bitwarden desktop

O agente existe só no aplicativo de desktop — extensão de navegador não serve. Três origens, em
ordem de preferência:

```bash
zypper info bitwarden          # repo-oss, mas costuma estar atrás da versão do Flathub
flatpak install --user flathub com.bitwarden.desktop
```

O Flatpak funciona: desde 2025 o aplicativo detecta o `FLATPAK_ID` e cria o soquete dentro da
própria pasta de dados, que é visível para o sistema. Não precisa de `flatpak override`.

| Origem | Caminho do soquete |
|---|---|
| Flatpak | `~/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock` |
| `.rpm` ou pacote do repositório | `~/.bitwarden-ssh-agent.sock` |

Guias antigos afirmam que o Flatpak não serve. Era verdade antes do aplicativo passar a tratar o
caso; confira o caminho acima antes de trocar de pacote por causa disso.

## 2. Chave no cofre

No Bitwarden, novo item do tipo **Chave SSH**. Ele gera o par ou aceita uma chave existente
colada. A privada nunca sai do cofre.

## 3. Ativar o agente

**Configurações → Agente SSH → Ativar agente SSH.** Junto vem *Pedir autorização ao usar o
agente*:

| Opção | Efeito |
|---|---|
| Sempre | confirma cada assinatura — um `git push` pede duas ou três |
| Nunca | qualquer processo seu assina em silêncio com o cofre destrancado |
| Lembrar até que o cofre seja bloqueado | aprova uma vez por chave; renova quando o cofre tranca |

A terceira é o meio-termo, e aí o que passa a valer é o **tempo de bloqueio do cofre**
(Configurações → Segurança): com "Nunca", a lembrança é permanente e o efeito vira o da segunda
linha.

O soquete nasce quando a opção é marcada. Sem ele, nada adiante funciona:

```bash
ls -l ~/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock   # tipo 's' no início
```

## 4. Apontar o `SSH_AUTH_SOCK`

Uma configuração serve para os dois mundos — terminal e aplicativos abertos pelo menu do KDE,
que não leem `~/.bashrc`:

```bash
mkdir -p ~/.config/environment.d
cat > ~/.config/environment.d/10-bitwarden-ssh-agent.conf <<'EOT'
SSH_AUTH_SOCK=${HOME}/.var/app/com.bitwarden.desktop/data/.bitwarden-ssh-agent.sock
EOT
```

Use `${HOME}`, não `%h`: o `%h` é especificador de unidade do systemd e não é expandido em
`environment.d`. Vale a partir do próximo login; confira com:

```bash
systemctl --user show-environment | grep SSH_AUTH_SOCK
```

Para usar antes de sair da sessão, `export SSH_AUTH_SOCK=<caminho>` no terminal.

## 5. Conferir

```bash
ssh-add -l          # impressões digitais das chaves do cofre
ssh-add -L          # as públicas, no formato do authorized_keys
```

| Mensagem | Causa |
|---|---|
| `Error connecting to agent: No such file or directory` | soquete não existe: agente desligado ou aplicativo fechado |
| `Could not open a connection to your authentication agent` | `SSH_AUTH_SOCK` não definido na sessão |
| `The agent has no identities` | cofre bloqueado, ou o item não é do tipo Chave SSH |

O `ssh-add -L` evita ter que copiar a chave pública pela interface — a saída já é a linha que o
GitHub e o `authorized_keys` esperam.

## 6. GitHub e servidores

No GitHub: **Settings → SSH and GPG keys → New SSH key**, colando a saída do `ssh-add -L`. Dê o
nome da máquina, para poder revogar uma só depois.

```bash
ssh -T git@github.com          # o Bitwarden pede aprovação
```

Em servidor próprio, `ssh-copy-id usuario@servidor` lê do agente e funciona igual.

## 7. git

```bash
git config --global user.name "Seu Nome"
git config --global user.email "voce@exemplo.com"
git config --global init.defaultBranch main
```

Repositório existente em HTTPS passa a SSH com `git remote set-url origin
git@github.com:usuario/repo.git`. Para converter todos de uma vez, sem tocar em cada um:

```bash
git config --global url."git@github.com:".insteadOf https://github.com/
```

Assinar commits com a mesma chave do cofre, sem GPG. Escolha a chave pelo nome que ela tem no
cofre — com mais de uma no agente, pegar a primeira da lista dá na errada:

```bash
ssh-add -L                                     # veja os nomes no fim de cada linha
KEY=$(ssh-add -L | grep -w 'NomeDaChave$')
git config --global gpg.format ssh
git config --global user.signingkey "$KEY"
git config --global commit.gpgsign true
```

Para o `git log --show-signature` conseguir verificar localmente, declare a chave como confiável:

```bash
mkdir -p ~/.config/git
printf '%s %s\n' "$(git config --global user.email)" "$(echo "$KEY" | cut -d' ' -f1,2)" \
  > ~/.config/git/allowed_signers
git config --global gpg.ssh.allowedSignersFile ~/.config/git/allowed_signers
```

No GitHub, a mesma chave precisa ser cadastrada **de novo**, com o tipo trocado para *Signing
Key* — o cadastro de *Authentication Key* não serve para assinar. Sem isso o commit sai assinado
e aparece como *Unverified* lá. Os dois cadastros são públicos e dá para conferir sem abrir o
site:

```bash
curl -s https://github.com/<usuario>.keys                            # autenticação
curl -s https://api.github.com/users/<usuario>/ssh_signing_keys      # assinatura
```

Compare com `ssh-add -L | cut -d' ' -f1,2` — o texto tem que bater exatamente.

Conferência ponta a ponta, num repositório descartável:

```bash
cd $(mktemp -d) && git init -q && echo x > a && git add a && git commit -qm teste
git log --show-signature -1        # "Good git signature for <seu e-mail>"
```

## Quando falha

**Funciona no terminal e não no editor** — falta o `environment.d` do passo 4, ou a sessão não
foi reiniciada depois de criá-lo.

**Parou do nada** — o cofre trancou por inatividade, ou o aplicativo foi fechado. O soquete some
junto com ele. Com `commit.gpgsign=true`, o `git commit` também falha, não só o `push`: destranque
o cofre, ou passe `--no-gpg-sign` naquele commit.

**A janela de aprovação não aparece** — o Bitwarden está na bandeja; abra a janela.

**Pede a senha da carteira do KDE ao entrar na sessão** — o Bitwarden sobe no autostart e busca
um segredo pelo portal, que precisa da `kdewallet` aberta. Conserto em
[solução de problemas](troubleshooting.pt-BR.md), "Carteira do KDE trancada".

**`No handler registered for 'sshagent.clearkeys'` no log** — o agente nunca subiu naquela
sessão. O log fica em `~/.var/app/com.bitwarden.desktop/config/Bitwarden/app.log`.

**O aplicativo desloga sozinho**, com `File backend error Incorrect secret` e `Access token key
not found` no mesmo log: o chaveiro em arquivo do sandbox corrompeu. Apagar resolve, ao custo de
novo login — os dados estão no servidor:

```bash
rm -rf ~/.var/app/com.bitwarden.desktop/data/keyrings
```

**Trocou Flatpak por pacote nativo, ou o contrário** — o caminho do soquete muda; refaça o passo 4.
