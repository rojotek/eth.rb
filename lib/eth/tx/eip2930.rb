# Copyright (c) 2016-2025 The Ruby-Eth Contributors
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Provides the {Eth} module.
module Eth

  # Provides the `Tx` module supporting various transaction types.
  module Tx

    # Provides legacy support for transactions on blockchains that do not
    # implement EIP-1559 but still want to utilize EIP-2718 envelopes.
    # Ref: https://eips.ethereum.org/EIPS/eip-2930
    class Eip2930

      # The EIP-155 Chain ID.
      # Ref: https://eips.ethereum.org/EIPS/eip-155
      attr_reader :chain_id

      # The transaction nonce provided by the signer.
      attr_reader :signer_nonce

      # The gas price for the transaction in Wei.
      attr_reader :gas_price

      # The gas limit for the transaction.
      attr_reader :gas_limit

      # The recipient address.
      attr_reader :destination

      # The transaction amount in Wei.
      attr_reader :amount

      # The transaction data payload.
      attr_reader :payload

      # An optional EIP-2930 access list.
      # Ref: https://eips.ethereum.org/EIPS/eip-2930
      attr_reader :access_list

      # The signature's `y`-parity byte (not `v`).
      attr_reader :signature_y_parity

      # The signature `r` value.
      attr_reader :signature_r

      # The signature `s` value.
      attr_reader :signature_s

      # The sender address.
      attr_reader :sender

      # The transaction type.
      attr_reader :type

      # Create a legacy type-1 (EIP-2930) transaction payload object that
      # can be prepared for envelope, signature and broadcast. Should not
      # be used unless there is no EIP-1559 support.
      # Ref: https://eips.ethereum.org/EIPS/eip-2930
      #
      #
      # @param params [Hash] all necessary transaction fields.
      # @option params [Integer] :chain_id the chain ID.
      # @option params [Integer] :nonce the signer nonce.
      # @option params [Integer] :gas_price the gas price.
      # @option params [Integer] :gas_limit the gas limit.
      # @option params [Eth::Address] :from the sender address.
      # @option params [Eth::Address] :to the reciever address.
      # @option params [Integer] :value the transaction value.
      # @option params [String] :data the transaction data payload.
      # @option params [Array] :access_list an optional access list.
      # @raise [ParameterError] if gas limit is too low.
      def initialize(params)
        fields = { recovery_id: nil, r: 0, s: 0 }.merge params

        # populate optional fields with serializable empty values
        fields[:chain_id] = Tx.sanitize_chain fields[:chain_id]
        fields[:from] = Tx.sanitize_address fields[:from]
        fields[:to] = Tx.sanitize_address fields[:to]
        fields[:value] = Tx.sanitize_amount fields[:value]
        fields[:data] = Tx.sanitize_data fields[:data]

        # ensure sane values for all mandatory fields
        fields = Tx.validate_params fields
        fields = Tx.validate_legacy_params fields
        fields[:access_list] = Tx.sanitize_list fields[:access_list]

        # ensure gas limit is not too low
        minimum_cost = Tx.estimate_intrinsic_gas fields[:data], fields[:access_list]
        raise ParameterError, "Transaction gas limit is too low, try #{minimum_cost}!" if fields[:gas_limit].to_i < minimum_cost

        # populate class attributes
        @signer_nonce = fields[:nonce].to_i
        @gas_price = fields[:gas_price].to_i
        @gas_limit = fields[:gas_limit].to_i
        @sender = fields[:from].to_s
        @destination = fields[:to].to_s
        @amount = fields[:value].to_i
        @payload = fields[:data]
        @access_list = fields[:access_list]

        # the signature v is set to the chain id for unsigned transactions
        @signature_y_parity = fields[:recovery_id]
        @chain_id = fields[:chain_id]

        # the signature fields are empty for unsigned transactions.
        @signature_r = fields[:r]
        @signature_s = fields[:s]

        # last but not least, set the type.
        @type = TYPE_2930
      end

      # Overloads the constructor for decoding raw transactions and creating unsigned copies.
      konstructor :decode, :unsigned_copy

      # Decodes a raw transaction hex into an {Eth::Tx::Eip2930}
      # transaction object.
      #
      # @param hex [String] the raw transaction hex-string.
      # @return [Eth::Tx::Eip2930] transaction payload.
      # @raise [TransactionTypeError] if transaction type is invalid.
      # @raise [ParameterError] if transaction is missing fields.
      # @raise [DecoderError] if transaction decoding fails.
      def decode(hex)
        hex = Util.remove_hex_prefix hex
        type = hex[0, 2]
        raise TransactionTypeError, "Invalid transaction type #{type}!" if type.to_i(16) != TYPE_2930

        bin = Util.hex_to_bin hex[2..]
        tx = Rlp.decode bin

        # decoded transactions always have 8 + 3 fields, even if they are empty or zero
        raise ParameterError, "Transaction missing fields!" if tx.size < 8

        # populate the 8 payload fields
        chain_id = Util.deserialize_big_endian_to_int tx[0]
        nonce = Util.deserialize_big_endian_to_int tx[1]
        gas_price = Util.deserialize_big_endian_to_int tx[2]
        gas_limit = Util.deserialize_big_endian_to_int tx[3]
        to = Util.bin_to_hex tx[4]
        value = Util.deserialize_big_endian_to_int tx[5]
        data = tx[6]
        access_list = tx[7]

        # populate class attributes
        @chain_id = chain_id.to_i
        @signer_nonce = nonce.to_i
        @gas_price = gas_price.to_i
        @gas_limit = gas_limit.to_i
        @destination = to.to_s
        @amount = value.to_i
        @payload = data
        @access_list = access_list

        # populate the 3 signature fields
        if tx.size == 8
          _set_signature(nil, 0, 0)
        elsif tx.size == 11
          recovery_id = Util.bin_to_hex(tx[8]).to_i(16)
          r = Util.bin_to_hex tx[9]
          s = Util.bin_to_hex tx[10]

          # allows us to force-setting a signature if the transaction is signed already
          _set_signature(recovery_id, r, s)
        else
          raise DecoderError, "Cannot decode EIP-2930 payload!"
        end

        # last but not least, set the type.
        @type = TYPE_2930

        unless recovery_id.nil?
          # recover sender address
          v = Chain.to_v recovery_id, chain_id
          public_key = Signature.recover(unsigned_hash, "#{r.rjust(64, "0")}#{s.rjust(64, "0")}#{v.to_s(16)}", chain_id)
          address = Util.public_key_to_address(public_key).to_s
          @sender = Tx.sanitize_address address
        else
          # keep the 'from' field blank
          @sender = Tx.sanitize_address nil
        end
      end

      # Creates an unsigned copy of a transaction payload.
      #
      # @param tx [Eth::Tx::Eip2930] an EIP-2930 transaction payload.
      # @return [Eth::Tx::Eip2930] an unsigned EIP-2930 transaction payload.
      # @raise [TransactionTypeError] if transaction type does not match.
      def unsigned_copy(tx)

        # not checking transaction validity unless it's of a different class
        raise TransactionTypeError, "Cannot copy transaction of different payload type!" unless tx.instance_of? Tx::Eip2930

        # populate class attributes
        @signer_nonce = tx.signer_nonce
        @gas_price = tx.gas_price
        @gas_limit = tx.gas_limit
        @destination = tx.destination
        @amount = tx.amount
        @payload = tx.payload
        @access_list = tx.access_list
        @chain_id = tx.chain_id

        # force-set signature to unsigned
        _set_signature(nil, 0, 0)

        # keep the 'from' field blank
        @sender = Tx.sanitize_address nil

        # last but not least, set the type.
        @type = TYPE_2930
      end

      # Sign the transaction with a given key.
      #
      # @param key [Eth::Key] the key-pair to use for signing.
      # @return [String] a transaction hash.
      # @raise [Signature::SignatureError] if transaction is already signed.
      # @raise [Signature::SignatureError] if sender address does not match signing key.
      def sign(key)
        if Tx.signed? self
          raise Signature::SignatureError, "Transaction is already signed!"
        end

        # ensure the sender address matches the given key
        unless @sender.nil? or sender.empty?
          signer_address = Tx.sanitize_address key.address.to_s
          from_address = Tx.sanitize_address @sender
          raise Signature::SignatureError, "Signer does not match sender" unless signer_address == from_address
        end

        # sign a keccak hash of the unsigned, encoded transaction
        signature = key.sign(unsigned_hash, @chain_id)
        r, s, v = Signature.dissect signature
        recovery_id = Chain.to_recovery_id v.to_i(16), @chain_id
        @signature_y_parity = recovery_id
        @signature_r = r
        @signature_s = s
        return hash
      end

      # Encodes a raw transaction object, wraps it in an EIP-2718 envelope
      # with an EIP-2930 type prefix.
      #
      # @return [String] a raw, RLP-encoded EIP-2930 type transaction object.
      # @raise [Signature::SignatureError] if the transaction is not yet signed.
      def encoded
        unless Tx.signed? self
          raise Signature::SignatureError, "Transaction is not signed!"
        end
        tx_data = []
        tx_data.push Util.serialize_int_to_big_endian @chain_id
        tx_data.push Util.serialize_int_to_big_endian @signer_nonce
        tx_data.push Util.serialize_int_to_big_endian @gas_price
        tx_data.push Util.serialize_int_to_big_endian @gas_limit
        tx_data.push Util.hex_to_bin @destination
        tx_data.push Util.serialize_int_to_big_endian @amount
        tx_data.push Rlp::Sedes.binary.serialize @payload
        tx_data.push Rlp::Sedes.infer(@access_list).serialize @access_list
        tx_data.push Util.serialize_int_to_big_endian @signature_y_parity
        tx_data.push Util.serialize_int_to_big_endian @signature_r
        tx_data.push Util.serialize_int_to_big_endian @signature_s
        tx_encoded = Rlp.encode tx_data

        # create an EIP-2718 envelope with EIP-2930 type payload
        tx_type = Util.serialize_int_to_big_endian @type
        return "#{tx_type}#{tx_encoded}"
      end

      # Gets the encoded, enveloped, raw transaction hex.
      #
      # @return [String] the raw transaction hex.
      def hex
        Util.bin_to_hex encoded
      end

      # Gets the transaction hash.
      #
      # @return [String] the transaction hash.
      def hash
        Util.bin_to_hex Util.keccak256 encoded
      end

      # Encodes the unsigned transaction payload in an EIP-2930 envelope,
      # required for signing.
      #
      # @return [String] an RLP-encoded, unsigned, enveloped EIP-2930 transaction.
      def unsigned_encoded
        tx_data = []
        tx_data.push Util.serialize_int_to_big_endian @chain_id
        tx_data.push Util.serialize_int_to_big_endian @signer_nonce
        tx_data.push Util.serialize_int_to_big_endian @gas_price
        tx_data.push Util.serialize_int_to_big_endian @gas_limit
        tx_data.push Util.hex_to_bin @destination
        tx_data.push Util.serialize_int_to_big_endian @amount
        tx_data.push Rlp::Sedes.binary.serialize @payload
        tx_data.push Rlp::Sedes.infer(@access_list).serialize @access_list
        tx_encoded = Rlp.encode tx_data

        # create an EIP-2718 envelope with EIP-2930 type payload (unsigned)
        tx_type = Util.serialize_int_to_big_endian @type
        return "#{tx_type}#{tx_encoded}"
      end

      # Gets the sign-hash required to sign a raw transaction.
      #
      # @return [String] a Keccak-256 hash of an unsigned transaction.
      def unsigned_hash
        Util.keccak256 unsigned_encoded
      end

      private

      # Force-sets an existing signature of a decoded transaction.
      def _set_signature(recovery_id, r, s)
        @signature_y_parity = recovery_id
        @signature_r = r
        @signature_s = s
      end
    end
  end
end
