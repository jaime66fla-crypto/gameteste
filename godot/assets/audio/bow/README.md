# Efeitos do arco

Sons originais, produzidos por síntese procedural offline, sem gravações ou amostras de terceiros. Não são gravações de um arco real.

- bow_draw_0..2.wav: 0,94 s, textura irregular de fibras sob tensão e pequenas ressonâncias de flexão da madeira.
- bow_release_0..2.wav: 0,48 s, estalo inicial, vibração curta e amortecida da corda, ressonâncias da madeira e passagem da flecha.
- PCM mono de 16 bits, 44.100 Hz. Pico limitado a 0,78 antes do ganho do jogo, com bordas suavizadas.

Reprodução pelo scripts/audio/bow_audio.gd, disparada pelo bow_controller.gd: começo da puxada, atualização de tensão, cancelamento com fade de 25 ms e disparo somente quando a flecha é lançada. Três variantes e pequenas alterações de pitch evitam repetição idêntica. O som de puxar não reinicia em loop quando o arco já está tensionado.

Para recriar os WAV, executar tools/audio/build_bow_sfx.py com Python 3. Apenas biblioteca padrão.
