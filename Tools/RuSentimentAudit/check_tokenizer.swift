import Foundation
@main struct Check {
 static func main() throws {
  struct Case: Decodable { let id: String; let text: String; let inputIds: [Int]; let attentionMask: [Int]; let tokenTypeIds: [Int] }
  struct Reference: Decodable { let cases: [Case] }
  let ref = try JSONDecoder().decode(Reference.self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
  let tokenizer = try DeviceRussianTokenizer(vocabURL: URL(fileURLWithPath: CommandLine.arguments[2]))
  for c in ref.cases {
   let e = try tokenizer.encode(c.text)
   guard e.inputIds == c.inputIds, e.attentionMask == c.attentionMask, e.tokenTypeIds == c.tokenTypeIds else {
    print("MISMATCH",c.id, e.inputIds.prefix(30),c.inputIds.prefix(30)); exit(1)
   }
  }
  print("Exact tokenizer parity:",ref.cases.count)
 }
}
