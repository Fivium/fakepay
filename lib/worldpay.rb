require 'digest/md5'

module WorldPay

  SIGNATURE_DELIMITER = ';'
  SIGNATURE_FIELDS_KEY = 'signatureFields'
  SIGNATURE_KEY = 'signature'

  def self.validate_md5_hash params, md5_key
    signature_fields = params[SIGNATURE_FIELDS_KEY]

    if signature_fields.nil?
      return false
    end

    raw_signature = md5_key + SIGNATURE_DELIMITER + signature_fields
    signature_fields.split(':').each do |field|
      raw_signature += SIGNATURE_DELIMITER + params[field]
    end

    return params[SIGNATURE_KEY] === Digest::MD5.hexdigest(raw_signature)
  end

end