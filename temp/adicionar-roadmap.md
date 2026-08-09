1.  Em uma lista enumerada, apertar <CR> para "descer" parte de uma linha não
inclui a linha gerada na lista automaticamente. Ex:

    ```(indesejado)
    
    -- Antes

    1. texto
    2. texto{{<CR> aqui}} texto

    -- Depois

    1. texto
    2. texto
    texto

    ```

    Automatizar a geração da enumeração ou criar um keymap que execute `<CR> +
    enumeração`.

    Nota: o resultado ocorre igualmente mesmo se o `<CR>` for inserido após o espaço,
    logo antes do primeiro caractere `t` do segundo `texto` da linha. Esse comportamento
    deve ser mantido.

    ```(desejado)
    -- Antes

    1. texto
    2. texto{{<CR> aqui}} texto

    -- Depois

    1. texto
    2. texto
    3. texto
    ```

2.  Considerar a extração do módulo de markdown (como foi feito com o syntax) e
    a aplicação a arquivos não pkm (opcional, ligado por padrão). Ex: wrap
    sensível a headers e blocos de código.

3.  O highlight de comentários falha quando o elemento final acaba em
    parênteses. Por exemplo, último parênteses no texto abaixo aparece sem o
    highlight, porque o sistema considera que o penúltimo parêntese já é o
    "segundo parêntese de fechamento", quando na verdade é o primeiro (pois o
    antepenúltimo fecha apenas o texto "provavelmente como heading nível 2"):

    ```
    ((O sistema de heurísticas também deve ser capaz, quando solicitado, de criar
    ou completar um espécie de "mapa do conteúdo", o qual envolverá os assuntos,
    referências e trechos relevantes, formas de cobrança, heurísticas utilizadas,
    dentre outros. Essa e uma ideia em concepção, que pode ou não ser desenvolvida.
    O provável local desse mapa será o guia de estudos de cada disciplina
    (provavelmente como heading nível 2))).
    ```

    Verifique e corrija outras possíveis falhas do highlight.
