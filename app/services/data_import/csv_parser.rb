# Lê o CSV de importação de contatos tolerando as variações que aparecem na prática
# quando o arquivo vem de Excel em português, de um ERP ou da Receita.
#
# Três coisas que o parser antigo não aguentava e que custaram caro:
#
# 1. Separador. `CSV.new(..., headers: true)` assume vírgula; o Excel em pt-BR exporta
#    com ponto-e-vírgula. O arquivo inteiro virava uma coluna só e nenhum contato era
#    reconhecido.
# 2. Encoding. O código anterior fazia force_encoding('UTF-8') e, quando inválido,
#    `encode('UTF-16le', invalid: :replace, replace: '')` — que **apaga** o byte. Um
#    arquivo Latin-1 importava "Caçamba" como "Caamba", sem erro nenhum.
# 3. Cabeçalho. Só casava a chave exata em minúsculo; `NOME`, `E-MAIL` e `Telefone`
#    eram ignorados e viravam custom_attributes.
class DataImport::CsvParser
  CANDIDATE_DELIMITERS = [',', ';', "\t", '|'].freeze

  # Chave canônica => grafias aceitas, já normalizadas (minúsculo, sem acento,
  # pontuação virando "_"). "E-MAIL" normaliza para "e_mail", "Razão Social" para
  # "razao_social".
  HEADER_ALIASES = {
    'name' => %w[name nome nome_completo nome_do_contato full_name fullname contato],
    'email' => %w[email e_mail mail correio correio_eletronico],
    'phone_number' => %w[phone_number phone telefone celular whatsapp fone tel numero numero_de_telefone],
    'company' => %w[company company_name empresa razao_social organizacao nome_da_empresa],
    'city' => %w[city cidade municipio],
    'identifier' => %w[identifier identificador id_externo]
  }.freeze

  CANONICAL_BY_ALIAS = HEADER_ALIASES.each_with_object({}) do |(canonical, aliases), map|
    aliases.each { |a| map[a] = canonical }
  end.freeze

  # Caracteres invisíveis que vêm junto ao copiar de WhatsApp, PDF ou planilha:
  # marcas de direção de texto, espaços de largura zero, BOM no meio do campo e
  # hífen opcional. Nenhum deles é visível, e todos quebram validação de telefone
  # e de e-mail.
  INVISIBLE_CHARS = /[­​-‏‪-‮⁠-⁤﻿]/

  def initialize(raw_bytes)
    @raw = raw_bytes
  end

  def each_row
    return enum_for(:each_row) unless block_given?

    csv.each { |row| yield normalize_row(row) }
  end

  def headers
    csv.first&.headers || []
  end

  def delimiter
    @delimiter ||= detect_delimiter
  end

  # Nome do encoding usado, para o relatório da importação.
  def encoding_used
    text && @encoding_used
  end

  private

  def csv
    CSV.new(StringIO.new(text), headers: true, header_converters: ->(header) { normalize_header(header) }, col_sep: delimiter)
  end

  # UTF-8 primeiro. Se não for UTF-8 válido, transcodifica de Windows-1252 (superset
  # do Latin-1, cobre as aspas e o travessão do Word) em vez de descartar bytes.
  def text
    @text ||= begin
      candidate = @raw.dup.force_encoding('UTF-8')
      if candidate.valid_encoding?
        @encoding_used = 'UTF-8'
      else
        candidate = @raw.dup.force_encoding('Windows-1252').encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
        @encoding_used = 'Windows-1252'
      end
      candidate.delete_prefix("\u{FEFF}")
    end
  end

  # Escolhe o separador que produz mais colunas no cabeçalho. Empate ou arquivo de
  # coluna única caem na vírgula, que é o padrão do Chatwoot.
  def detect_delimiter
    header_line = text.each_line.first.to_s
    best = CANDIDATE_DELIMITERS.max_by { |d| column_count(header_line, d) }
    column_count(header_line, best) > 1 ? best : ','
  end

  def column_count(line, delimiter)
    CSV.parse_line(line, col_sep: delimiter)&.size || 0
  rescue CSV::MalformedCSVError
    0
  end

  def normalize_header(header)
    key = fold(header)
    CANONICAL_BY_ALIAS[key] || key
  end

  # minúsculo, sem acento, pontuação e espaços viram "_"
  def fold(value)
    value.to_s
         .unicode_normalize(:nfd)
         .gsub(/\p{Mn}/, '')
         .downcase
         .strip
         .gsub(/[^a-z0-9]+/, '_')
         .gsub(/\A_+|_+\z/, '')
  end

  def normalize_row(row)
    row.each do |key, value|
      row[key] = clean_value(value)
    end
    row
  end

  def clean_value(value)
    return value unless value.is_a?(String)

    cleaned = value.gsub(INVISIBLE_CHARS, '').strip
    cleaned.empty? ? nil : cleaned
  end
end
