---
updated: AAAA-MM-DD
tier: 2
checked: AAAA-MM-DD\n---

# Aprendizados

<!-- TETO: 100 linhas fora de blocos auto. Uma linha por fato, formato grepável: `- [AAAA-MM-DD] [tag] fato — consequência`.
     O que foi tentado ou decidido leva veredito depois da tag: [✓] testado e mantido, [✗] tentado e descartado (nunca apagar), [↻ AAAA-MM-DD] substituído pela entrada dessa data.
     Grave a linha no momento em que o fato aparece, não só no encerramento: sessão que compacta antes perde o que não foi escrito. -->

## Preferências do usuário

- [AAAA-MM-DD] [prefs] exemplo — fazer X em vez de Y

## Pegadinhas (versão, API, CI)

- [AAAA-MM-DD] [versão] o que acontece — o que fazer

## Erros a não repetir

- [AAAA-MM-DD] [tag] erro — correção

## Decisões e o porquê

- [AAAA-MM-DD] [decisão] [✓] o quê — porquê e como foi testado
- [AAAA-MM-DD] [decisão] [✗] o que foi tentado — por que não serviu
- [AAAA-MM-DD] [decisão] [↻ AAAA-MM-DD] o que valia — trocado pela entrada dessa data

## Memória de longo prazo

<!-- TETO: 15 linhas. Um ponteiro por tópico: `- [AAAA-MM-DD] [tag] → memory/<tag>.md — N entradas: resumo`.
     Tag que estoura desce INTEIRO para `memory/<tag>.md` (mesmo formato de linha, vereditos inclusos) e vira 1 ponteiro aqui.
     Nada é apagado. A pasta não é importada: recupere com `index.sh <termo>` ou `index.sh -x`. -->

- [AAAA-MM-DD] [tag] → memory/tag.md — N entradas: resumo do que tem lá

