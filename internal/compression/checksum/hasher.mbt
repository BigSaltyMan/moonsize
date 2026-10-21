///|
/// Hasher is a trait for computing rolling checksums over byte data.
/// Aligned with moonbitlang/x CryptoHasher but returns UInt for 32-bit checksums.
pub(open) trait Hasher {
  /// Returns the hash output size in bytes.
  fn size(Self) -> Int
  /// Resets the hasher to its initial state.
  fn reset(Self) -> Unit
  /// Feeds bytes into the running hash.
  fn update(Self, BytesView) -> Unit
  /// Returns the current checksum value.
  fn checksum(Self) -> UInt
}
