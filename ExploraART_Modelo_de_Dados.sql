-- =====================================================================
-- ExploraART - Modelo de dados (MySQL 8.0.16 ou superior)
-- Criação completa da base de dados, de acordo com os requisitos 1 a 32.
--
-- Para recriar a base de dados do zero (APAGA todos os dados existentes),
-- retire os dois traços da linha seguinte:
-- DROP DATABASE IF EXISTS explora_art;
-- =====================================================================

CREATE DATABASE IF NOT EXISTS explora_art DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE explora_art;

-- ---------------------------------------------------------------------
-- 1. CONTA E UTILIZADORES (Req. 2, 3, 4, 5, 6, 7, 8)
-- ---------------------------------------------------------------------
CREATE TABLE utilizadores (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    email VARCHAR(100) NOT NULL,
    password_hash VARCHAR(255) NOT NULL COMMENT 'Hash da palavra-chave (nunca o texto)',
    papel ENUM('registado', 'subscrito', 'administrador') NOT NULL DEFAULT 'registado',
    estado ENUM('ativo', 'suspenso', 'banido') NOT NULL DEFAULT 'ativo',
    email_confirmado BOOLEAN NOT NULL DEFAULT FALSE,
    tentativas_falhadas INT NOT NULL DEFAULT 0 COMMENT 'Bloqueio apos 5 falhas consecutivas',
    bloqueado_ate DATETIME NULL COMMENT 'Fim do bloqueio temporario de 15 minutos',
    token_recuperacao VARCHAR(255) NULL COMMENT 'Hash do token; valido 1 hora, uso unico (passa a NULL depois de usado)',
    expiracao_token DATETIME NULL,
    foto_perfil VARCHAR(255) NULL,
    aceitou_termos_em DATETIME NULL COMMENT 'Aceitacao dos termos e da politica de privacidade',
    consentimento_feed BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Consentimento para o feed personalizado (Req. 23)',
    data_registo TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_utilizadores_username (username),
    UNIQUE KEY uq_utilizadores_email (email),
    KEY idx_utilizadores_estado (estado)
) ENGINE=InnoDB;

CREATE TABLE definicoes_conta (
    user_id INT PRIMARY KEY,
    aceita_cookies BOOLEAN NULL DEFAULT NULL COMMENT 'NULL = ainda nao respondeu (consentimento ativo, RGPD)',
    notificacoes_internas BOOLEAN NOT NULL DEFAULT TRUE,
    notificacoes_email BOOLEAN NOT NULL DEFAULT TRUE,
    notificacoes_push BOOLEAN NOT NULL DEFAULT TRUE,
    notificar_comentarios BOOLEAN NOT NULL DEFAULT TRUE,
    notificar_gostos BOOLEAN NOT NULL DEFAULT TRUE,
    notificar_respostas BOOLEAN NOT NULL DEFAULT TRUE,
    alto_contraste BOOLEAN NOT NULL DEFAULT FALSE,
    tamanho_texto ENUM('pequeno', 'medio', 'grande') NOT NULL DEFAULT 'medio',
    leitor_ecra BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT fk_definicoes_conta_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE sancoes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    admin_id INT NULL,
    tipo ENUM('suspensao', 'banimento') NOT NULL,
    motivo TEXT NOT NULL,
    data_inicio DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_fim DATETIME NULL COMMENT 'Escolhida pelo administrador na suspensao; NULL no banimento',
    KEY idx_sancoes_user (user_id, data_inicio),
    CONSTRAINT ck_sancoes_fim CHECK ((tipo = 'suspensao' AND data_fim IS NOT NULL) OR (tipo = 'banimento' AND data_fim IS NULL)),
    CONSTRAINT fk_sancoes_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_sancoes_admin FOREIGN KEY (admin_id) REFERENCES utilizadores(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 2. SUBSCRIÇÕES E PAGAMENTOS (Req. 15, 16, 17)
-- ---------------------------------------------------------------------
CREATE TABLE subscricoes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    metodo_pagamento ENUM('mb_way', 'multibanco') NOT NULL,
    estado ENUM('pendente', 'ativa', 'cancelada', 'expirada') NOT NULL DEFAULT 'pendente',
    renovacao_automatica BOOLEAN NOT NULL DEFAULT TRUE,
    data_inicio DATETIME NULL COMMENT 'Preenchida quando o pagamento e confirmado',
    data_fim DATETIME NULL,
    data_criacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_subscricoes_user (user_id, estado),
    KEY idx_subscricoes_fim (data_fim),
    CONSTRAINT fk_subscricoes_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE pagamentos (
    id INT AUTO_INCREMENT PRIMARY KEY,
    subscricao_id INT NULL,
    user_id INT NULL COMMENT 'Fica a NULL quando a conta e eliminada (registo anonimizado)',
    valor DECIMAL(8, 2) NOT NULL,
    metodo ENUM('mb_way', 'multibanco') NOT NULL,
    estado ENUM('pendente', 'pago', 'falhado') NOT NULL DEFAULT 'pendente',
    entidade VARCHAR(10) NULL COMMENT 'Multibanco',
    referencia_multibanco VARCHAR(20) NULL,
    referencia_sibs VARCHAR(64) NULL COMMENT 'Identificador da transacao na SIBS (simulada)',
    data_criacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_pagamento DATETIME NULL,
    KEY idx_pagamentos_user (user_id, data_criacao),
    KEY idx_pagamentos_subscricao (subscricao_id),
    CONSTRAINT fk_pagamentos_subscricao FOREIGN KEY (subscricao_id) REFERENCES subscricoes(id) ON DELETE SET NULL,
    CONSTRAINT fk_pagamentos_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 3. TAGS (Req. 11, 27)
-- ---------------------------------------------------------------------
CREATE TABLE tags (
    id INT AUTO_INCREMENT PRIMARY KEY,
    nome VARCHAR(50) NOT NULL,
    UNIQUE KEY uq_tags_nome (nome)
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 4. COMUNIDADES (Req. 30)
-- ---------------------------------------------------------------------
CREATE TABLE comunidades (
    id INT AUTO_INCREMENT PRIMARY KEY,
    criador_id INT NULL COMMENT 'A aplicacao transfere a administracao antes de eliminar o criador',
    nome VARCHAR(100) NOT NULL,
    descricao TEXT NULL,
    tipo ENUM('publica', 'privada') NOT NULL DEFAULT 'publica',
    data_criacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_comunidades_nome (nome),
    CONSTRAINT fk_comunidades_criador FOREIGN KEY (criador_id) REFERENCES utilizadores(id) ON DELETE SET NULL
) ENGINE=InnoDB;

CREATE TABLE comunidade_membros (
    comunidade_id INT NOT NULL,
    user_id INT NOT NULL,
    papel ENUM('membro', 'administrador') NOT NULL DEFAULT 'membro',
    estado ENUM('pendente', 'ativo') NOT NULL DEFAULT 'ativo' COMMENT 'pendente = pedido de adesao a comunidade privada',
    data_pedido TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_adesao DATETIME NULL COMMENT 'Entrada efetiva; define o membro mais antigo',
    PRIMARY KEY (comunidade_id, user_id),
    KEY idx_comunidade_membros_user (user_id),
    CONSTRAINT fk_comunidade_membros_comunidade FOREIGN KEY (comunidade_id) REFERENCES comunidades(id) ON DELETE CASCADE,
    CONSTRAINT fk_comunidade_membros_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 5. PUBLICAÇÕES E CONTEÚDOS (Req. 11, 12, 25, 27, 32)
-- ---------------------------------------------------------------------
CREATE TABLE publicacoes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    autor_id INT NOT NULL,
    comunidade_id INT NULL COMMENT 'Preenchido nas publicacoes do forum de uma comunidade',
    tipo_conteudo ENUM('texto', 'imagem', 'video', 'musica', 'documento') NOT NULL,
    formato_ficheiro ENUM('pdf', 'jpeg', 'png', 'mp3', 'mp4') NULL,
    titulo VARCHAR(150) NOT NULL,
    texto_corpo TEXT NULL,
    url_cloud VARCHAR(255) NULL COMMENT 'Caminho/URL do ficheiro (armazenamento local, preparado para cloud)',
    tamanho_ficheiro INT NULL COMMENT 'Tamanho em bytes',
    data_publicacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_edicao DATETIME NULL,
    KEY idx_publicacoes_data (data_publicacao),
    KEY idx_publicacoes_autor (autor_id, data_publicacao),
    KEY idx_publicacoes_tipo (tipo_conteudo, data_publicacao),
    KEY idx_publicacoes_comunidade (comunidade_id, data_publicacao),
    FULLTEXT KEY ft_publicacoes_texto (titulo, texto_corpo),
    CONSTRAINT ck_publicacoes_tipo_formato CHECK (
        formato_ficheiro IS NULL
        OR (tipo_conteudo = 'musica' AND formato_ficheiro = 'mp3')
        OR (tipo_conteudo = 'imagem' AND formato_ficheiro IN ('jpeg', 'png'))
        OR (tipo_conteudo = 'video' AND formato_ficheiro = 'mp4')
        OR (tipo_conteudo = 'documento' AND formato_ficheiro = 'pdf')
    ),
    CONSTRAINT fk_publicacoes_autor FOREIGN KEY (autor_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_publicacoes_comunidade FOREIGN KEY (comunidade_id) REFERENCES comunidades(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE publicacao_tags (
    publicacao_id INT NOT NULL,
    tag_id INT NOT NULL,
    PRIMARY KEY (publicacao_id, tag_id),
    KEY idx_publicacao_tags_tag (tag_id),
    CONSTRAINT fk_publicacao_tags_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE CASCADE,
    CONSTRAINT fk_publicacao_tags_tag FOREIGN KEY (tag_id) REFERENCES tags(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 6. COMENTÁRIOS, GOSTOS, FAVORITOS, VISUALIZAÇÕES (Req. 10, 12, 13, 23, 25)
-- ---------------------------------------------------------------------
CREATE TABLE comentarios (
    id INT AUTO_INCREMENT PRIMARY KEY,
    publicacao_id INT NOT NULL,
    autor_id INT NULL COMMENT 'NULL num comentario eliminado que mantem respostas',
    comentario_pai_id INT NULL COMMENT 'Respostas encadeadas, sem limite de profundidade',
    texto TEXT NOT NULL COMMENT 'Texto vazio quando eliminado = TRUE',
    eliminado BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Aparece como [comentario eliminado] se tem respostas',
    data_comentario TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_edicao DATETIME NULL,
    KEY idx_comentarios_publicacao (publicacao_id, data_comentario),
    KEY idx_comentarios_autor (autor_id),
    KEY idx_comentarios_pai (comentario_pai_id),
    CONSTRAINT fk_comentarios_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE CASCADE,
    CONSTRAINT fk_comentarios_autor FOREIGN KEY (autor_id) REFERENCES utilizadores(id) ON DELETE SET NULL,
    CONSTRAINT fk_comentarios_pai FOREIGN KEY (comentario_pai_id) REFERENCES comentarios(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE gostos (
    user_id INT NOT NULL,
    publicacao_id INT NOT NULL,
    data_gosto TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, publicacao_id),
    KEY idx_gostos_publicacao (publicacao_id),
    CONSTRAINT fk_gostos_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_gostos_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE favoritos (
    user_id INT NOT NULL,
    publicacao_id INT NOT NULL,
    data_adicao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, publicacao_id),
    KEY idx_favoritos_publicacao (publicacao_id),
    CONSTRAINT fk_favoritos_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_favoritos_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE visualizacoes (
    user_id INT NOT NULL,
    publicacao_id INT NOT NULL,
    segundos_totais INT NOT NULL DEFAULT 0 COMMENT 'Tempo de visualizacao acumulado (feed personalizado)',
    ultima_visualizacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, publicacao_id),
    KEY idx_visualizacoes_publicacao (publicacao_id),
    CONSTRAINT fk_visualizacoes_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_visualizacoes_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 7. DOWNLOADS (Req. 18, 19)
-- ---------------------------------------------------------------------
CREATE TABLE downloads (
    user_id INT NOT NULL,
    publicacao_id INT NOT NULL,
    data_download TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (user_id, publicacao_id),
    KEY idx_downloads_publicacao (publicacao_id),
    CONSTRAINT fk_downloads_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_downloads_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 8. MODERAÇÃO (Req. 20, 21)
-- ---------------------------------------------------------------------
CREATE TABLE denuncias (
    id INT AUTO_INCREMENT PRIMARY KEY,
    reportador_id INT NOT NULL,
    publicacao_id INT NULL COMMENT 'Fica a NULL se a publicacao for eliminada, mantendo o registo da decisao',
    titulo_publicacao VARCHAR(150) NULL COMMENT 'Copia do titulo no momento da denuncia',
    motivo TEXT NOT NULL,
    estado ENUM('pendente', 'em_analise', 'resolvida', 'ignorada') NOT NULL DEFAULT 'pendente',
    acao_tomada ENUM('ignorar', 'eliminar_publicacao', 'suspender_autor', 'banir_autor') NULL,
    resolvida_por INT NULL,
    data_denuncia TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_resolucao DATETIME NULL,
    UNIQUE KEY uq_denuncias_reportador_publicacao (reportador_id, publicacao_id),
    KEY idx_denuncias_publicacao (publicacao_id, estado),
    CONSTRAINT fk_denuncias_reportador FOREIGN KEY (reportador_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_denuncias_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE SET NULL,
    CONSTRAINT fk_denuncias_resolvida_por FOREIGN KEY (resolvida_por) REFERENCES utilizadores(id) ON DELETE SET NULL
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 9. NOTIFICAÇÕES (Req. 22)
-- ---------------------------------------------------------------------
CREATE TABLE notificacoes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    tipo ENUM('comentario', 'gosto', 'resposta', 'sistema') NOT NULL,
    mensagem VARCHAR(255) NOT NULL,
    lida BOOLEAN NOT NULL DEFAULT FALSE,
    link_referencia VARCHAR(255) NULL,
    data_notificacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY idx_notificacoes_user (user_id, lida, data_notificacao),
    CONSTRAINT fk_notificacoes_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 10. MÚSICA E PLAYLISTS (Req. 28, 29)
-- ---------------------------------------------------------------------
CREATE TABLE playlists (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    nome VARCHAR(100) NOT NULL,
    data_criacao TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uq_playlists_user_nome (user_id, nome),
    CONSTRAINT fk_playlists_user FOREIGN KEY (user_id) REFERENCES utilizadores(id) ON DELETE CASCADE
) ENGINE=InnoDB;

CREATE TABLE playlist_musicas (
    playlist_id INT NOT NULL,
    publicacao_id INT NOT NULL COMMENT 'Publicacao do tipo musica (validado na aplicacao)',
    ordem INT NOT NULL,
    PRIMARY KEY (playlist_id, publicacao_id),
    KEY idx_playlist_musicas_ordem (playlist_id, ordem),
    KEY idx_playlist_musicas_publicacao (publicacao_id),
    CONSTRAINT fk_playlist_musicas_playlist FOREIGN KEY (playlist_id) REFERENCES playlists(id) ON DELETE CASCADE,
    CONSTRAINT fk_playlist_musicas_publicacao FOREIGN KEY (publicacao_id) REFERENCES publicacoes(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- 11. MENSAGENS DIRETAS (Req. 31)
-- ---------------------------------------------------------------------
CREATE TABLE mensagens_diretas (
    id INT AUTO_INCREMENT PRIMARY KEY,
    remetente_id INT NOT NULL,
    destinatario_id INT NOT NULL,
    texto TEXT NOT NULL,
    data_envio TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    data_edicao DATETIME NULL COMMENT 'Edicao permitida ate 5 minutos depois do envio',
    data_leitura DATETIME NULL COMMENT 'NULL = enviada; preenchida = lida',
    KEY idx_mensagens_conversa (remetente_id, destinatario_id, data_envio),
    KEY idx_mensagens_caixa (destinatario_id, data_leitura),
    CONSTRAINT fk_mensagens_remetente FOREIGN KEY (remetente_id) REFERENCES utilizadores(id) ON DELETE CASCADE,
    CONSTRAINT fk_mensagens_destinatario FOREIGN KEY (destinatario_id) REFERENCES utilizadores(id) ON DELETE CASCADE
) ENGINE=InnoDB;

-- ---------------------------------------------------------------------
-- VISTAS
-- ---------------------------------------------------------------------

-- Áreas do menu (Req. 32): Música = MP3, Livros = PDF, Arte = imagem e vídeo.
-- As publicações só de texto não têm área e aparecem apenas no feed.
-- Considera apenas as publicações do feed geral (fora do fórum das comunidades).
CREATE OR REPLACE VIEW v_publicacoes_area AS
SELECT
    p.id,
    p.autor_id,
    p.tipo_conteudo,
    p.titulo,
    p.data_publicacao,
    CASE p.tipo_conteudo
        WHEN 'musica' THEN 'musica'
        WHEN 'documento' THEN 'livros'
        WHEN 'imagem' THEN 'arte'
        WHEN 'video' THEN 'arte'
        ELSE NULL
    END AS area
FROM publicacoes p
WHERE p.comunidade_id IS NULL;

-- Painel de moderação (Req. 21): uma linha por publicação denunciada,
-- com o total de denúncias, da mais para a menos denunciada.
CREATE OR REPLACE VIEW v_painel_denuncias AS
SELECT
    p.id AS publicacao_id,
    p.titulo,
    p.autor_id,
    COUNT(*) AS total_denuncias,
    MIN(d.data_denuncia) AS primeira_denuncia
FROM denuncias d
JOIN publicacoes p ON p.id = d.publicacao_id
WHERE d.estado IN ('pendente', 'em_analise')
GROUP BY p.id, p.titulo, p.autor_id
ORDER BY total_denuncias DESC, primeira_denuncia ASC;
