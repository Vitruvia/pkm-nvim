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
