# -*- encoding : ascii-8bit -*-

require "spec_helper"

describe Tx::Eip7702 do
  subject(:anvil) {
    31337.freeze
  }

  subject(:authorization_list) {
    [
      Tx::Eip7702::Authorization.new(
        chain_id: anvil,
        address: "700b6a60ce7eaaea56f065753d8dcb9653dbad35",
        nonce: 2,
        recovery_id: 0,
        r: "a4f2c5243c3d6d82168ef35b3d3df1e50cefee1bc212c769bd1968061c395260",
        s: "7f346c1804300b96d687a90ce5bcea0883c12bc45b6a8a294e29ff7c02b42a65",
      ),
      Tx::Eip7702::Authorization.new(
        chain_id: Chain::ETHEREUM,
        address: "700b6a60ce7eaaea56f065753d8dcb9653dbad35",
        nonce: 11,
        r: "acec76e844690cf2f58317d13d910b270cf0b9e307db8094402dc46b4f456a81",
        s: "570d6ea163a505896aa2674d56810033cd4d03b13787065b5abe57cde485e52a",
        recovery_id: 0,
      ),
    ]
  }

  subject(:access_list) {
    [
      [
        "de0b295669a9fd93d5f28d9ec85e40f4cb697bae",
        [
          "0000000000000000000000000000000000000000000000000000000000000003",
          "0000000000000000000000000000000000000000000000000000000000000007",
        ],
      ],
      [
        "0xa0ee7a142d267c1f36714e4a8f75612f20a79720",
        [],
      ],
      [
        "0xcb98643b8786950f0461f3b0edf99d88f274574d",
        [],
      ],
      [
        "0xd2135cfb216b74109775236e36d4b433f1df507b",
        [],
      ],
      [
        "0x700b6a60ce7eaaea56f065753d8dcb9653dbad35",
        [],
      ],
    ]
  }

  subject(:type04) {
    Tx.new({
             chain_id: anvil,
             nonce: 1,
             priority_fee: 1000000000,
             max_gas_fee: 2200000000,
             gas_limit: 554330,
             to: "0xa0ee7a142d267c1f36714e4a8f75612f20a79720",
             value: 0,
             data: "0xa6d0ad6100000000000000000000000000000000000000000000000000000000000000200000000000000000000000000000000000000000000000000000000000000002000000000000000000000000000000000000000000000000000000000000004000000000000000000000000000000000000000000000000000000000000000c00000000000000000000000000000000000000000000000000000000000000060000000000000000000000000cb98643b8786950f0461f3b0edf99d88f274574d00000000000000000000000000000000000000000000000000038d7ea4c6800000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000060000000000000000000000000d2135cfb216b74109775236e36d4b433f1df507b00000000000000000000000000000000000000000000000000071afd498d00000000000000000000000000000000000000000000000000000000000000000000",
             access_list: access_list,
             authorization_list: authorization_list,
           })
  }

  subject(:testnet) { Key.new(priv: "0xc6c633f85d3f9a4705623b1d9bd1122a1a9196cd53dd352505e895fcbb8452ef") }

  subject(:tx) {
    Tx.new({
             nonce: 0,
             priority_fee: 0,
             max_gas_fee: Unit::WEI,
             gas_limit: Tx::DEFAULT_GAS_LIMIT,
             authorizations: authorization_list,
           })
  }

  subject(:cow) { Key.new(priv: Util.keccak256("cow")) }

  describe ".initialize" do
    it "creates EIP-7702 transaction objects" do
      expect(tx).to be
      expect(tx).to be_instance_of Tx::Eip7702
    end

    it "doesn't create invalid transaction objects"
  end

  describe ".sign" do
    it "signs the default transaction" do
      tx.sign(cow)
      expect(tx.signature_y_parity).to eq 0
      expect(tx.signature_r).to eq "1a82a35841305639f04570d210f2b88ed7af20d951b3020b28375f245d1edf28"
      expect(tx.signature_s).to eq "359d4e5634774b0e25c913db88b20fec8d0dcd29788da4c71e9a82722a6920f5"
    end

    it "it does not sign a transaction twice" do
      expect { type04.hash }.to raise_error StandardError, "Transaction is not signed!"
      expect(testnet.address.to_s).to eq "0x4762119a7249823D18aec7EAB73258B2D5061Dd8"
      type04.sign(testnet)
      expect { type04.sign(testnet) }.to raise_error StandardError, "Transaction is already signed!"
    end

    it "checks for a valid sender"
  end

  describe ".encoded" do
    it "encodes the default transaction"

    it "encodes a known pectra devnet-6 transaction"
  end

  describe ".hex" do
    it "hexes the default transaction"

    it "hexes a known pectra devnet-6 transaction"
  end

  describe ".hash" do
    it "hashes the default transaction"

    it "hashes a known pectra devnet-6 transaction"
  end

  describe ".copy" do
    it "can duplicate transactions"
  end
end
