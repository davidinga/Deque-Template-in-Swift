/*
https://github.com/apple/swift-collections/blob/main/Documentation/Deque.md
*/

@frozen
public struct Deque<Element> {
  @usableFromInline
  internal typealias _Slot = _DequeSlot

  @usableFromInline
  internal var _storage: _Storage

  @inlinable
  internal init(_storage: _Storage) {
    self._storage = _storage
  }
  
  @inlinable
  public init(minimumCapacity: Int) {
    self._storage = _Storage(minimumCapacity: minimumCapacity)
  }
}

@usableFromInline
@frozen
internal struct _DequeSlot {
  @usableFromInline
  internal var position: Int

  @inlinable
  @inline(__always)
  init(at position: Int) {
    assert(position >= 0)
    self.position = position
  }
}

extension _DequeSlot {
  @inlinable
  @inline(__always)
  internal static var zero: Self { Self(at: 0) }

  @inlinable
  @inline(__always)
  internal func advanced(by delta: Int) -> Self {
    Self(at: position &+ delta)
  }

  @inlinable
  @inline(__always)
  internal func orIfZero(_ value: Int) -> Self {
    guard position > 0 else { return Self(at: value) }
    return self
  }
}

extension _DequeSlot: CustomStringConvertible {
  @usableFromInline
  internal var description: String {
    "@\(position)"
  }
}

extension _DequeSlot: Equatable {
  @inlinable
  @inline(__always)
  static func ==(left: Self, right: Self) -> Bool {
    left.position == right.position
  }
}

extension _DequeSlot: Comparable {
  @inlinable
  @inline(__always)
  static func <(left: Self, right: Self) -> Bool {
    left.position < right.position
  }
}

extension Range where Bound == _DequeSlot {
  @inlinable
  @inline(__always)
  internal var _count: Int { upperBound.position - lowerBound.position }
}

extension Deque {
  @frozen
  @usableFromInline
  struct _Storage {
    @usableFromInline
    internal typealias _Buffer = ManagedBufferPointer<_DequeBufferHeader, Element>

    @usableFromInline
    internal var _buffer: _Buffer

    @inlinable
    @inline(__always)
    internal init(_buffer: _Buffer) {
      self._buffer = _buffer
    }
  }
}

extension Deque._Storage: CustomStringConvertible {
  @usableFromInline
  internal var description: String {
    "Deque<\(Element.self)>._Storage\(_buffer.header)"
  }
}

extension Deque._Storage {
  @inlinable
  internal init() {
    self.init(_buffer: _Buffer(unsafeBufferObject: _emptyDequeStorage))
  }

  @inlinable
  internal init(_ object: _DequeBuffer<Element>) {
    self.init(_buffer: _Buffer(unsafeBufferObject: object))
  }

  @inlinable
  internal init(minimumCapacity: Int) {
    let object = _DequeBuffer<Element>.create(
      minimumCapacity: minimumCapacity,
      makingHeaderWith: {
        #if os(OpenBSD)
        let capacity = minimumCapacity
        #else
        let capacity = $0.capacity
        #endif
        return _DequeBufferHeader(capacity: capacity, count: 0, startSlot: .zero)
      })
    self.init(_buffer: _Buffer(unsafeBufferObject: object))
  }
}

extension Deque._Storage {
  #if COLLECTIONS_INTERNAL_CHECKS
  @usableFromInline @inline(never) @_effects(releasenone)
  internal func _checkInvariants() {
    _buffer.withUnsafeMutablePointerToHeader { $0.pointee._checkInvariants() }
  }
  #else
  @inlinable @inline(__always)
  internal func _checkInvariants() {}
  #endif
}

extension Deque._Storage {
  @inlinable
  @inline(__always)
  internal var identity: AnyObject { _buffer.buffer }


  @inlinable
  @inline(__always)
  internal var capacity: Int {
    _buffer.withUnsafeMutablePointerToHeader { $0.pointee.capacity }
  }

  @inlinable
  @inline(__always)
  internal var count: Int {
    _buffer.withUnsafeMutablePointerToHeader { $0.pointee.count }
  }

  @inlinable
  @inline(__always)
  internal var startSlot: _DequeSlot {
    _buffer.withUnsafeMutablePointerToHeader { $0.pointee.startSlot
    }
  }
}

extension Deque._Storage {
  @usableFromInline
  internal typealias Index = Int

  @usableFromInline
  internal typealias _UnsafeHandle = Deque._UnsafeHandle

  @inlinable
  @inline(__always)
  internal func read<R>(_ body: (_UnsafeHandle) throws -> R) rethrows -> R {
    try _buffer.withUnsafeMutablePointers { header, elements in
      let handle = _UnsafeHandle(header: header,
                                 elements: elements,
                                 isMutable: false)
      return try body(handle)
    }
  }

  @inlinable
  @inline(__always)
  internal func update<R>(_ body: (_UnsafeHandle) throws -> R) rethrows -> R {
    try _buffer.withUnsafeMutablePointers { header, elements in
      let handle = _UnsafeHandle(header: header,
                                 elements: elements,
                                 isMutable: true)
      return try body(handle)
    }
  }
}

extension Deque._Storage {
  @inlinable
  @inline(__always)
  internal mutating func isUnique() -> Bool {
    _buffer.isUniqueReference()
  }

  @inlinable
  @inline(__always)
  internal mutating func ensureUnique() {
    if isUnique() { return }
    self._makeUniqueCopy()
  }

  @inlinable
  @inline(never)
  internal mutating func _makeUniqueCopy() {
    self = self.read { $0.copyElements() }
  }

  @inlinable
  @inline(__always)
  internal static var growthFactor: Double { 1.5 }

  @usableFromInline
  internal func _growCapacity(
    to minimumCapacity: Int,
    linearly: Bool
  ) -> Int {
    if linearly { return Swift.max(capacity, minimumCapacity) }
    return Swift.max(Int((Self.growthFactor * Double(capacity)).rounded(.up)),
                     minimumCapacity)
  }

  @inlinable
  @inline(__always)
  internal mutating func ensureUnique(
    minimumCapacity: Int,
    linearGrowth: Bool = false
  ) {
    let unique = isUnique()
    if _slowPath(capacity < minimumCapacity || !unique) {
      _ensureUnique(minimumCapacity: minimumCapacity, linearGrowth: linearGrowth)
    }
  }

  @inlinable
  internal mutating func _ensureUnique(
    minimumCapacity: Int,
    linearGrowth: Bool
  ) {
    if capacity >= minimumCapacity {
      assert(!self.isUnique())
      self = self.read { $0.copyElements() }
    } else if isUnique() {
      let minimumCapacity = _growCapacity(to: minimumCapacity, linearly: linearGrowth)
      self = self.update { source in
        source.moveElements(minimumCapacity: minimumCapacity)
      }
    } else {
      let minimumCapacity = _growCapacity(to: minimumCapacity, linearly: linearGrowth)
      self = self.read { source in
        source.copyElements(minimumCapacity: minimumCapacity)
      }
    }
  }
}

@usableFromInline
internal struct _DequeBufferHeader {
  @usableFromInline
  var capacity: Int

  @usableFromInline
  var count: Int

  @usableFromInline
  var startSlot: _DequeSlot

  @usableFromInline
  init(capacity: Int, count: Int, startSlot: _DequeSlot) {
    self.capacity = capacity
    self.count = count
    self.startSlot = startSlot
    _checkInvariants()
  }

  #if COLLECTIONS_INTERNAL_CHECKS
  @usableFromInline @inline(never) @_effects(releasenone)
  internal func _checkInvariants() {
    precondition(capacity >= 0)
    precondition(count >= 0 && count <= capacity)
    precondition(startSlot.position >= 0 && startSlot.position <= capacity)
  }
  #else
  @inlinable @inline(__always)
  internal func _checkInvariants() {}
  #endif
}

extension _DequeBufferHeader: CustomStringConvertible {
  @usableFromInline
  internal var description: String {
    "(capacity: \(capacity), count: \(count), startSlot: \(startSlot))"
  }
}

@_fixed_layout
@usableFromInline
internal class _DequeBuffer<Element>: ManagedBuffer<_DequeBufferHeader, Element> {
  @inlinable
  deinit {
    self.withUnsafeMutablePointers { header, elements in
      header.pointee._checkInvariants()

      let capacity = header.pointee.capacity
      let count = header.pointee.count
      let startSlot = header.pointee.startSlot

      if startSlot.position + count <= capacity {
        (elements + startSlot.position).deinitialize(count: count)
      } else {
        let firstRegion = capacity - startSlot.position
        (elements + startSlot.position).deinitialize(count: firstRegion)
        elements.deinitialize(count: count - firstRegion)
      }
    }
  }
}

extension _DequeBuffer: CustomStringConvertible {
  @usableFromInline
  internal var description: String {
    withUnsafeMutablePointerToHeader { "_DequeStorage<\(Element.self)>\($0.pointee)" }
  }
}

@usableFromInline
internal let _emptyDequeStorage = _DequeBuffer<Void>.create(
  minimumCapacity: 0,
  makingHeaderWith: { _ in
    _DequeBufferHeader(capacity: 0, count: 0, startSlot: .init(at: 0))
  })

extension Deque {
  @frozen
  @usableFromInline
  internal struct _UnsafeHandle {
    @usableFromInline
    let _header: UnsafeMutablePointer<_DequeBufferHeader>
    @usableFromInline
    let _elements: UnsafeMutablePointer<Element>
    #if DEBUG
    @usableFromInline
    let _isMutable: Bool
    #endif

    @inlinable
    @inline(__always)
    init(
      header: UnsafeMutablePointer<_DequeBufferHeader>,
      elements: UnsafeMutablePointer<Element>,
      isMutable: Bool
    ) {
      self._header = header
      self._elements = elements
      #if DEBUG
      self._isMutable = isMutable
      #endif
    }
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  @inline(__always)
  func assertMutable() {
    #if DEBUG
    assert(_isMutable)
    #endif
  }
}

extension Deque._UnsafeHandle {
  @usableFromInline
  internal typealias Slot = _DequeSlot

  @inlinable
  @inline(__always)
  var header: _DequeBufferHeader {
    _header.pointee
  }

  @inlinable
  @inline(__always)
  var capacity: Int {
    _header.pointee.capacity
  }

  @inlinable
  @inline(__always)
  var count: Int {
    get { _header.pointee.count }
    nonmutating set { _header.pointee.count = newValue }
  }

  @inlinable
  @inline(__always)
  var startSlot: Slot {
    get { _header.pointee.startSlot }
    nonmutating set { _header.pointee.startSlot = newValue }
  }

  @inlinable
  @inline(__always)
  func ptr(at slot: Slot) -> UnsafeMutablePointer<Element> {
    assert(slot.position >= 0 && slot.position <= capacity)
    return _elements + slot.position
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  @inline(__always)
  var mutableBuffer: UnsafeMutableBufferPointer<Element> {
    assertMutable()
    return .init(start: _elements, count: _header.pointee.capacity)
  }

  @inlinable
  internal func buffer(for range: Range<Slot>) -> UnsafeBufferPointer<Element> {
    assert(range.upperBound.position <= capacity)
    return .init(start: _elements + range.lowerBound.position, count: range._count)
  }

  @inlinable
  @inline(__always)
  internal func mutableBuffer(for range: Range<Slot>) -> UnsafeMutableBufferPointer<Element> {
    assertMutable()
    return .init(mutating: buffer(for: range))
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  @inline(__always)
  internal var limSlot: Slot {
    Slot(at: capacity)
  }

  @inlinable
  internal func slot(after slot: Slot) -> Slot {
    assert(slot.position < capacity)
    let position = slot.position + 1
    if position >= capacity {
      return Slot(at: 0)
    }
    return Slot(at: position)
  }

  @inlinable
  internal func slot(before slot: Slot) -> Slot {
    assert(slot.position < capacity)
    if slot.position == 0 { return Slot(at: capacity - 1) }
    return Slot(at: slot.position - 1)
  }

  @inlinable
  internal func slot(_ slot: Slot, offsetBy delta: Int) -> Slot {
    assert(slot.position <= capacity)
    let position = slot.position + delta
    if delta >= 0 {
      if position >= capacity { return Slot(at: position - capacity) }
    } else {
      if position < 0 { return Slot(at: position + capacity) }
    }
    return Slot(at: position)
  }

  @inlinable
  @inline(__always)
  internal var endSlot: Slot {
    slot(startSlot, offsetBy: count)
  }

  @inlinable
  internal func slot(forOffset offset: Int) -> Slot {
    assert(offset >= 0)
    assert(offset <= capacity)
    let position = startSlot.position &+ offset
    guard position < capacity else { return Slot(at: position &- capacity) }
    return Slot(at: position)
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  internal func segments() -> _UnsafeWrappedBuffer<Element> {
    let wrap = capacity - startSlot.position
    if count <= wrap {
      return .init(start: ptr(at: startSlot), count: count)
    }
    return .init(first: ptr(at: startSlot), count: wrap,
                 second: ptr(at: .zero), count: count - wrap)
  }

  @inlinable
  internal func segments(
    forOffsets offsets: Range<Int>
  ) -> _UnsafeWrappedBuffer<Element> {
    assert(offsets.lowerBound >= 0 && offsets.upperBound <= count)
    let lower = slot(forOffset: offsets.lowerBound)
    let upper = slot(forOffset: offsets.upperBound)
    if offsets.count == 0 || lower < upper {
      return .init(start: ptr(at: lower), count: offsets.count)
    }
    return .init(first: ptr(at: lower), count: capacity - lower.position,
                 second: ptr(at: .zero), count: upper.position)
  }

  @inlinable
  @inline(__always)
  internal func mutableSegments() -> _UnsafeMutableWrappedBuffer<Element> {
    assertMutable()
    return .init(mutating: segments())
  }

  @inlinable
  @inline(__always)
  internal func mutableSegments(
    forOffsets range: Range<Int>
  ) -> _UnsafeMutableWrappedBuffer<Element> {
    assertMutable()
    return .init(mutating: segments(forOffsets: range))
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  internal func availableSegments() -> _UnsafeMutableWrappedBuffer<Element> {
    assertMutable()
    let endSlot = self.endSlot
    guard count < capacity else { return .init(start: ptr(at: endSlot), count: 0) }
    if endSlot < startSlot { return .init(mutableBuffer(for: endSlot ..< startSlot)) }
    return .init(mutableBuffer(for: endSlot ..< limSlot),
                 mutableBuffer(for: .zero ..< startSlot))
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  @discardableResult
  func initialize(
    at start: Slot,
    from source: UnsafeBufferPointer<Element>
  ) -> Slot {
    assert(start.position + source.count <= capacity)
    guard source.count > 0 else { return start }
    ptr(at: start).initialize(from: source.baseAddress!, count: source.count)
    return Slot(at: start.position + source.count)
  }

  @inlinable
  @inline(__always)
  @discardableResult
  func moveInitialize(
    at start: Slot,
    from source: UnsafeMutableBufferPointer<Element>
  ) -> Slot {
    assert(start.position + source.count <= capacity)
    guard source.count > 0 else { return start }
    ptr(at: start).moveInitialize(from: source.baseAddress!, count: source.count)
    return Slot(at: start.position + source.count)
  }

  @inlinable
  @inline(__always)
  @discardableResult
  public func move(
    from source: Slot,
    to target: Slot,
    count: Int
  ) -> (source: Slot, target: Slot) {
    assert(count >= 0)
    assert(source.position + count <= self.capacity)
    assert(target.position + count <= self.capacity)
    guard count > 0 else { return (source, target) }
    ptr(at: target).moveInitialize(from: ptr(at: source), count: count)
    return (slot(source, offsetBy: count), slot(target, offsetBy: count))
  }
}



extension Deque._UnsafeHandle {
  @inlinable
  internal func copyElements() -> Deque._Storage {
    let object = _DequeBuffer<Element>.create(
      minimumCapacity: capacity,
      makingHeaderWith: { _ in header })
    let result = Deque._Storage(_buffer: ManagedBufferPointer(unsafeBufferObject: object))
    guard self.count > 0 else { return result }
    result.update { target in
      let source = self.segments()
      target.initialize(at: startSlot, from: source.first)
      if let second = source.second {
        target.initialize(at: .zero, from: second)
      }
    }
    return result
  }

  @inlinable
  internal func copyElements(minimumCapacity: Int) -> Deque._Storage {
    assert(minimumCapacity >= count)
    let object = _DequeBuffer<Element>.create(
      minimumCapacity: minimumCapacity,
      makingHeaderWith: {
        #if os(OpenBSD)
        let capacity = minimumCapacity
        #else
        let capacity = $0.capacity
        #endif
        return _DequeBufferHeader(
          capacity: capacity,
          count: count,
          startSlot: .zero)
      })
    let result = Deque._Storage(_buffer: ManagedBufferPointer(unsafeBufferObject: object))
    guard count > 0 else { return result }
    result.update { target in
      assert(target.count == count && target.startSlot.position == 0)
      let source = self.segments()
      let next = target.initialize(at: .zero, from: source.first)
      if let second = source.second {
        target.initialize(at: next, from: second)
      }
    }
    return result
  }

  @inlinable
  internal func moveElements(minimumCapacity: Int) -> Deque._Storage {
    assertMutable()
    let count = self.count
    assert(minimumCapacity >= count)
    let object = _DequeBuffer<Element>.create(
      minimumCapacity: minimumCapacity,
      makingHeaderWith: {
        #if os(OpenBSD)
        let capacity = minimumCapacity
        #else
        let capacity = $0.capacity
        #endif
        return _DequeBufferHeader(
          capacity: capacity,
          count: count,
          startSlot: .zero)
      })
    let result = Deque._Storage(_buffer: ManagedBufferPointer(unsafeBufferObject: object))
    guard count > 0 else { return result }
    result.update { target in
      let source = self.mutableSegments()
      let next = target.moveInitialize(at: .zero, from: source.first)
      if let second = source.second {
        target.moveInitialize(at: next, from: second)
      }
    }
    self.count = 0
    return result
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  internal func withUnsafeSegment<R>(
    startingAt start: Int,
    maximumCount: Int?,
    _ body: (UnsafeBufferPointer<Element>) throws -> R
  ) rethrows -> (end: Int, result: R) {
    assert(start <= count)
    guard start < count else {
      return try (count, body(UnsafeBufferPointer(start: nil, count: 0)))
    }
    let endSlot = self.endSlot

    let segmentStart = self.slot(forOffset: start)
    let segmentEnd = segmentStart < endSlot ? endSlot : limSlot
    let count = Swift.min(maximumCount ?? Int.max, segmentEnd.position - segmentStart.position)
    let result = try body(UnsafeBufferPointer(start: ptr(at: segmentStart), count: count))
    return (start + count, result)
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  internal func uncheckedReplaceInPlace<C: Collection>(
    inOffsets range: Range<Int>,
    with newElements: C
  ) where C.Element == Element {
    assertMutable()
    assert(range.upperBound <= count)
    assert(newElements.count == range.count)
    guard !range.isEmpty else { return }
    let target = mutableSegments(forOffsets: range)
    target.assign(from: newElements)
  }
}

// MARK: Appending
extension Deque._UnsafeHandle {
  @inlinable
  internal func uncheckedAppend(_ element: Element) {
    assertMutable()
    assert(count < capacity)
    ptr(at: endSlot).initialize(to: element)
    count += 1
  }

  @inlinable
  internal func uncheckedAppend(contentsOf source: UnsafeBufferPointer<Element>) {
    assertMutable()
    assert(count + source.count <= capacity)
    guard source.count > 0 else { return }
    let c = self.count
    count += source.count
    let gap = mutableSegments(forOffsets: c ..< count)
    gap.initialize(from: source)
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  internal func uncheckedPrepend(_ element: Element) {
    assertMutable()
    assert(count < capacity)
    let slot = self.slot(before: startSlot)
    ptr(at: slot).initialize(to: element)
    startSlot = slot
    count += 1
  }

  @inlinable
  internal func uncheckedPrepend(contentsOf source: UnsafeBufferPointer<Element>) {
    assertMutable()
    assert(count + source.count <= capacity)
    guard source.count > 0 else { return }
    let oldStart = startSlot
    let newStart = self.slot(startSlot, offsetBy: -source.count)
    startSlot = newStart
    count += source.count

    let gap = mutableWrappedBuffer(between: newStart, and: oldStart)
    gap.initialize(from: source)
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  internal func uncheckedInsert<C: Collection>(
    contentsOf newElements: __owned C,
    count newCount: Int,
    atOffset offset: Int
  ) where C.Element == Element {
    assertMutable()
    assert(offset <= count)
    assert(newElements.count == newCount)
    guard newCount > 0 else { return }
    let gap = openGap(ofSize: newCount, atOffset: offset)
    gap.initialize(from: newElements)
  }

  @inlinable
  internal func mutableWrappedBuffer(
    between start: Slot,
    and end: Slot
  ) -> _UnsafeMutableWrappedBuffer<Element> {
    assert(start.position <= capacity)
    assert(end.position <= capacity)
    if start < end {
      return .init(start: ptr(at: start), count: end.position - start.position)
    }
    return .init(
      first: ptr(at: start), count: capacity - start.position,
      second: ptr(at: .zero), count: end.position)
  }

  @inlinable
  internal func openGap(
    ofSize gapSize: Int,
    atOffset offset: Int
  ) -> _UnsafeMutableWrappedBuffer<Element> {
    assertMutable()
    assert(offset >= 0 && offset <= self.count)
    assert(self.count + gapSize <= capacity)
    assert(gapSize > 0)

    let headCount = offset
    let tailCount = count - offset
    if tailCount <= headCount {

      let originalEnd = self.slot(startSlot, offsetBy: count)
      let newEnd = self.slot(startSlot, offsetBy: count + gapSize)
      let gapStart = self.slot(forOffset: offset)
      let gapEnd = self.slot(gapStart, offsetBy: gapSize)

      let sourceIsContiguous = gapStart <= originalEnd.orIfZero(capacity)
      let targetIsContiguous = gapEnd <= newEnd.orIfZero(capacity)

      if sourceIsContiguous && targetIsContiguous {
        move(from: gapStart, to: gapEnd, count: tailCount)
      } else if targetIsContiguous {
        assert(startSlot > originalEnd.orIfZero(capacity))
        move(from: .zero, to: Slot.zero.advanced(by: gapSize), count: originalEnd.position)
        move(from: gapStart, to: gapEnd, count: capacity - gapStart.position)
      } else if sourceIsContiguous {
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: newEnd.position)
        move(from: gapStart, to: gapEnd, count: tailCount - newEnd.position)
      } else {
        move(from: .zero, to: Slot.zero.advanced(by: gapSize), count: originalEnd.position)
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: gapSize)
        move(from: gapStart, to: gapEnd, count: tailCount - gapSize - originalEnd.position)
      }
      count += gapSize
      return mutableWrappedBuffer(between: gapStart, and: gapEnd.orIfZero(capacity))
    }

    let originalStart = self.startSlot
    let newStart = self.slot(originalStart, offsetBy: -gapSize)
    let gapEnd = self.slot(forOffset: offset)
    let gapStart = self.slot(gapEnd, offsetBy: -gapSize)

    let sourceIsContiguous = originalStart <= gapEnd.orIfZero(capacity)
    let targetIsContiguous = newStart <= gapStart.orIfZero(capacity)

    if sourceIsContiguous && targetIsContiguous {
      move(from: originalStart, to: newStart, count: headCount)
    } else if targetIsContiguous {
      assert(originalStart >= newStart)
      move(from: originalStart, to: newStart, count: capacity - originalStart.position)
      move(from: .zero, to: limSlot.advanced(by: -gapSize), count: gapEnd.position)
    } else if sourceIsContiguous {
      move(from: originalStart, to: newStart, count: capacity - newStart.position)
      move(from: Slot.zero.advanced(by: gapSize), to: .zero, count: gapStart.position)
    } else {
      move(from: originalStart, to: newStart, count: capacity - originalStart.position)
      move(from: .zero, to: limSlot.advanced(by: -gapSize), count: gapSize)
      move(from: Slot.zero.advanced(by: gapSize), to: .zero, count: gapStart.position)
    }
    startSlot = newStart
    count += gapSize
    return mutableWrappedBuffer(between: gapStart, and: gapEnd.orIfZero(capacity))
  }
}

extension Deque._UnsafeHandle {
  @inlinable
  internal func uncheckedRemoveFirst() -> Element {
    assertMutable()
    assert(count > 0)
    let result = ptr(at: startSlot).move()
    startSlot = slot(after: startSlot)
    count -= 1
    return result
  }

  @inlinable
  internal func uncheckedRemoveLast() -> Element {
    assertMutable()
    assert(count > 0)
    let slot = self.slot(forOffset: count - 1)
    let result = ptr(at: slot).move()
    count -= 1
    return result
  }

  @inlinable
  internal func uncheckedRemoveFirst(_ n: Int) {
    assertMutable()
    assert(count >= n)
    guard n > 0 else { return }
    let target = mutableSegments(forOffsets: 0 ..< n)
    target.deinitialize()
    startSlot = slot(startSlot, offsetBy: n)
    count -= n
  }

  @inlinable
  internal func uncheckedRemoveLast(_ n: Int) {
    assertMutable()
    assert(count >= n)
    guard n > 0 else { return }
    let target = mutableSegments(forOffsets: count - n ..< count)
    target.deinitialize()
    count -= n
  }

  @inlinable
  internal func uncheckedRemoveAll() {
    assertMutable()
    guard count > 0 else { return }
    let target = mutableSegments()
    target.deinitialize()
    count = 0
    startSlot = .zero
  }

  @inlinable
  internal func uncheckedRemove(offsets bounds: Range<Int>) {
    assertMutable()
    assert(bounds.lowerBound >= 0 && bounds.upperBound <= self.count)

    mutableSegments(forOffsets: bounds).deinitialize()
    closeGap(offsets: bounds)
  }

  @inlinable
  internal func closeGap(offsets bounds: Range<Int>) {
    assertMutable()
    assert(bounds.lowerBound >= 0 && bounds.upperBound <= self.count)
    let gapSize = bounds.count
    guard gapSize > 0 else { return }

    let gapStart = self.slot(forOffset: bounds.lowerBound)
    let gapEnd = self.slot(forOffset: bounds.upperBound)

    let headCount = bounds.lowerBound
    let tailCount = count - bounds.upperBound

    if headCount >= tailCount {
      let originalEnd = endSlot
      let newEnd = self.slot(forOffset: count - gapSize)

      let sourceIsContiguous = gapEnd < originalEnd.orIfZero(capacity)
      let targetIsContiguous = gapStart <= newEnd.orIfZero(capacity)
      if tailCount == 0 {
      } else if sourceIsContiguous && targetIsContiguous {
        move(from: gapEnd, to: gapStart, count: tailCount)
      } else if sourceIsContiguous {
        let c = capacity - gapStart.position
        assert(tailCount > c)
        let next = move(from: gapEnd, to: gapStart, count: c)
        move(from: next.source, to: .zero, count: tailCount - c)
      } else if targetIsContiguous {
        let next = move(from: gapEnd, to: gapStart, count: capacity - gapEnd.position)
        move(from: .zero, to: next.target, count: originalEnd.position)
      } else {
        var next = move(from: gapEnd, to: gapStart, count: capacity - gapEnd.position)
        next = move(from: .zero, to: next.target, count: gapSize)
        move(from: next.source, to: .zero, count: newEnd.position)
      }
      count -= gapSize
    } else {
      let originalStart = startSlot
      let newStart = slot(startSlot, offsetBy: gapSize)

      let sourceIsContiguous = originalStart < gapStart.orIfZero(capacity)
      let targetIsContiguous = newStart <= gapEnd.orIfZero(capacity)

      if headCount == 0 {
      } else if sourceIsContiguous && targetIsContiguous {
        move(from: originalStart, to: newStart, count: headCount)
      } else if sourceIsContiguous {
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: gapEnd.position)
        move(from: startSlot, to: newStart, count: headCount - gapEnd.position)
      } else if targetIsContiguous {
        move(from: .zero, to: gapEnd.advanced(by: -gapStart.position), count: gapStart.position)
        move(from: startSlot, to: newStart, count: headCount - gapStart.position)
      } else {
        move(from: .zero, to: Slot.zero.advanced(by: gapSize), count: gapStart.position)
        move(from: limSlot.advanced(by: -gapSize), to: .zero, count: gapSize)
        move(from: startSlot, to: newStart, count: headCount - gapEnd.position)
      }
      startSlot = newStart
      count -= gapSize
    }
  }
}

@frozen
@usableFromInline
internal struct _UnsafeWrappedBuffer<Element> {
  @usableFromInline
  internal let first: UnsafeBufferPointer<Element>

  @usableFromInline
  internal let second: UnsafeBufferPointer<Element>?

  @inlinable
  @inline(__always)
  internal init(
    _ first: UnsafeBufferPointer<Element>,
    _ second: UnsafeBufferPointer<Element>? = nil
  ) {
    self.first = first
    self.second = second
    assert(first.count > 0 || second == nil)
  }

  @inlinable
  internal init(
    start: UnsafePointer<Element>,
    count: Int
  ) {
    self.init(UnsafeBufferPointer(start: start, count: count))
  }

  @inlinable
  internal init(
    first start1: UnsafePointer<Element>,
    count count1: Int,
    second start2: UnsafePointer<Element>,
    count count2: Int
  ) {
    self.init(UnsafeBufferPointer(start: start1, count: count1),
              UnsafeBufferPointer(start: start2, count: count2))
  }

  @inlinable
  internal var count: Int { first.count + (second?.count ?? 0) }
}

@frozen
@usableFromInline
internal struct _UnsafeMutableWrappedBuffer<Element> {
  @usableFromInline
  internal let first: UnsafeMutableBufferPointer<Element>

  @usableFromInline
  internal let second: UnsafeMutableBufferPointer<Element>?

  @inlinable
  @inline(__always)
  internal init(
    _ first: UnsafeMutableBufferPointer<Element>,
    _ second: UnsafeMutableBufferPointer<Element>? = nil
  ) {
    self.first = first
    self.second = second?.count == 0 ? nil : second
    assert(first.count > 0 || second == nil)
  }

  @inlinable
  @inline(__always)
  internal init(
    _ first: UnsafeMutableBufferPointer<Element>.SubSequence,
    _ second: UnsafeMutableBufferPointer<Element>? = nil
  ) {
    self.init(UnsafeMutableBufferPointer(rebasing: first), second)
  }

  @inlinable
  @inline(__always)
  internal init(
    _ first: UnsafeMutableBufferPointer<Element>,
    _ second: UnsafeMutableBufferPointer<Element>.SubSequence
  ) {
    self.init(first, UnsafeMutableBufferPointer(rebasing: second))
  }

  @inlinable
  @inline(__always)
  internal init(
    start: UnsafeMutablePointer<Element>,
    count: Int
  ) {
    self.init(UnsafeMutableBufferPointer(start: start, count: count))
  }

  @inlinable
  @inline(__always)
  internal init(
    first start1: UnsafeMutablePointer<Element>,
    count count1: Int,
    second start2: UnsafeMutablePointer<Element>,
    count count2: Int
  ) {
    self.init(UnsafeMutableBufferPointer(start: start1, count: count1),
              UnsafeMutableBufferPointer(start: start2, count: count2))
  }

  @inlinable
  @inline(__always)
  internal init(mutating buffer: _UnsafeWrappedBuffer<Element>) {
    self.init(.init(mutating: buffer.first),
              buffer.second.map { .init(mutating: $0) })
  }
}

extension _UnsafeMutableWrappedBuffer {
  @inlinable
  @inline(__always)
  internal var count: Int { first.count + (second?.count ?? 0) }

  @inlinable
  internal func prefix(_ n: Int) -> Self {
    assert(n >= 0)
    if n >= self.count {
      return self
    }
    if n <= first.count {
      return Self(first.prefix(n))
    }
    return Self(first, second!.prefix(n - first.count))
  }

  @inlinable
  internal func suffix(_ n: Int) -> Self {
    assert(n >= 0)
    if n >= self.count {
      return self
    }
    guard let second = second else {
      return Self(first.suffix(n))
    }
    if n <= second.count {
      return Self(second.suffix(n))
    }
    return Self(first.suffix(n - second.count), second)
  }
}

extension _UnsafeMutableWrappedBuffer {
  @inlinable
  internal func deinitialize() {
    first.deinitialize()
    second?.deinitialize()
  }

  @inlinable
  @discardableResult
  internal func initialize<I: IteratorProtocol>(
    fromPrefixOf iterator: inout I
  ) -> Int
  where I.Element == Element {
    var copied = 0
    var gap = first
    var wrapped = false
    while true {
      if copied == gap.count {
        guard !wrapped, let second = second, second.count > 0 else { break }
        gap = second
        copied = 0
        wrapped = true
      }
      guard let next = iterator.next() else { break }
      (gap.baseAddress! + copied).initialize(to: next)
      copied += 1
    }
    return wrapped ? first.count + copied : copied
  }

  @inlinable
  internal func initialize<S: Sequence>(
    fromSequencePrefix elements: __owned S
  ) -> (iterator: S.Iterator, count: Int)
  where S.Element == Element {
    guard second == nil || first.count >= elements.underestimatedCount else {
      var it = elements.makeIterator()
      let copied = initialize(fromPrefixOf: &it)
      return (it, copied)
    }
    var (it, copied) = elements._copyContents(initializing: first)
    if copied == first.count, let second = second {
      var i = 0
      while i < second.count {
        guard let next = it.next() else { break }
        (second.baseAddress! + i).initialize(to: next)
        i += 1
      }
      copied += i
    }
    return (it, copied)
  }

  @inlinable
  internal func initialize<C: Collection>(
    from elements: __owned C
  ) where C.Element == Element {
    assert(self.count == elements.count)
    if let second = second {
      let wrap = elements.index(elements.startIndex, offsetBy: first.count)
      first.initializeAll(fromContentsOf: elements[..<wrap])
      second.initializeAll(fromContentsOf: elements[wrap...])
    } else {
      first.initializeAll(fromContentsOf: elements)
    }
  }

  @inlinable
  internal func assign<C: Collection>(
    from elements: C
  ) where C.Element == Element {
    assert(elements.count == self.count)
    deinitialize()
    initialize(from: elements)
  }
}

extension UnsafeMutableBufferPointer {
  @discardableResult
  @inlinable
  public func deinitialize() -> UnsafeMutableRawBufferPointer {
    guard let start = baseAddress else { return .init(start: nil, count: 0) }
    start.deinitialize(count: count)
    return .init(start: UnsafeMutableRawPointer(start),
                 count: count * MemoryLayout<Element>.stride)
  }
}

extension UnsafeMutableBufferPointer {
  @inlinable
  public func initialize<C: Collection>(
    fromContentsOf source: C
  ) -> Index
  where C.Element == Element {
    let count: Int? = source._withContiguousStorageIfAvailable_SR14663 {
      guard let sourceAddress = $0.baseAddress, !$0.isEmpty else {
        return 0
      }
      precondition(
        $0.count <= self.count,
        "buffer cannot contain every element from source."
      )
      baseAddress?.initialize(from: sourceAddress, count: $0.count)
      return $0.count
    }
    if let count = count {
      return startIndex.advanced(by: count)
    }

    var (iterator, copied) = source._copyContents(initializing: self)
    precondition(
      iterator.next() == nil,
      "buffer cannot contain every element from source."
    )
    return startIndex.advanced(by: copied)
  }

  @inlinable
  @_alwaysEmitIntoClient
  public func moveInitialize(fromContentsOf source: Self) -> Index {
    guard let sourceAddress = source.baseAddress, !source.isEmpty else {
      return startIndex
    }
    precondition(
      source.count <= self.count,
      "buffer cannot contain every element from source."
    )
    baseAddress?.moveInitialize(from: sourceAddress, count: source.count)
    return startIndex.advanced(by: source.count)
  }

  @inlinable
  @_alwaysEmitIntoClient
  public func moveInitialize(fromContentsOf source: Slice<Self>) -> Index {
    return moveInitialize(fromContentsOf: Self(rebasing: source))
  }

  @inlinable
  @_alwaysEmitIntoClient
  public func initializeElement(at index: Index, to value: Element) {
    assert(startIndex <= index && index < endIndex)
    let p = baseAddress.unsafelyUnwrapped.advanced(by: index)
    p.initialize(to: value)
  }

  @inlinable
  @_alwaysEmitIntoClient
  public func moveElement(from index: Index) -> Element {
    assert(startIndex <= index && index < endIndex)
    return baseAddress.unsafelyUnwrapped.advanced(by: index).move()
  }

  @inlinable
  @_alwaysEmitIntoClient
  public func deinitializeElement(at index: Index) {
    assert(startIndex <= index && index < endIndex)
    let p = baseAddress.unsafelyUnwrapped.advanced(by: index)
    p.deinitialize(count: 1)
  }
}

extension Slice {
  @inlinable
  @_alwaysEmitIntoClient
  public func initialize<C: Collection>(
    fromContentsOf source: C
  ) -> Index where Base == UnsafeMutableBufferPointer<C.Element> {
    let buffer = Base(rebasing: self)
    let index = buffer.initialize(fromContentsOf: source)
    let distance = buffer.distance(from: buffer.startIndex, to: index)
    return startIndex.advanced(by: distance)
  }
  
  @inlinable
  @_alwaysEmitIntoClient
  public func moveInitialize<Element>(
    fromContentsOf source: UnsafeMutableBufferPointer<Element>
  ) -> Index where Base == UnsafeMutableBufferPointer<Element> {
    let buffer = Base(rebasing: self)
    let index = buffer.moveInitialize(fromContentsOf: source)
    let distance = buffer.distance(from: buffer.startIndex, to: index)
    return startIndex.advanced(by: distance)
  }

  @inlinable
  @_alwaysEmitIntoClient
  public func moveInitialize<Element>(
    fromContentsOf source: Slice<UnsafeMutableBufferPointer<Element>>
  ) -> Index where Base == UnsafeMutableBufferPointer<Element> {
    let buffer = Base(rebasing: self)
    let index = buffer.moveInitialize(fromContentsOf: source)
    let distance = buffer.distance(from: buffer.startIndex, to: index)
    return startIndex.advanced(by: distance)
  }

  @discardableResult
  @inlinable
  @_alwaysEmitIntoClient
  public func deinitialize<Element>() -> UnsafeMutableRawBufferPointer
  where Base == UnsafeMutableBufferPointer<Element> {
    Base(rebasing: self).deinitialize()
  }

  @inlinable
  @_alwaysEmitIntoClient
  public func initializeElement<Element>(at index: Int, to value: Element)
  where Base == UnsafeMutableBufferPointer<Element> {
    assert(startIndex <= index && index < endIndex)
    base.baseAddress.unsafelyUnwrapped.advanced(by: index).initialize(to: value)
  }
}

#if swift(<5.8)
extension UnsafeMutableBufferPointer {
  @_alwaysEmitIntoClient
  public func update(repeating repeatedValue: Element) {
    guard let dstBase = baseAddress else { return }
    dstBase.update(repeating: repeatedValue, count: count)
  }
}
#endif

#if swift(<5.8)
extension Slice {
  @_alwaysEmitIntoClient
  public func update<Element>(repeating repeatedValue: Element)
  where Base == UnsafeMutableBufferPointer<Element> {
    Base(rebasing: self).update(repeating: repeatedValue)
  }
}
#endif

extension UnsafeMutableBufferPointer {
  @inlinable
  public func initialize(fromContentsOf source: Self) -> Index {
    guard source.count > 0 else { return 0 }
    precondition(
      source.count <= self.count,
      "buffer cannot contain every element from source.")
    baseAddress.unsafelyUnwrapped.initialize(
      from: source.baseAddress.unsafelyUnwrapped,
      count: source.count)
    return source.count
  }

  @inlinable
  public func initialize(fromContentsOf source: Slice<Self>) -> Index {
    let sourceCount = source.count
    guard sourceCount > 0 else { return 0 }
    precondition(
      sourceCount <= self.count,
      "buffer cannot contain every element from source.")
    baseAddress.unsafelyUnwrapped.initialize(
      from: source.base.baseAddress.unsafelyUnwrapped + source.startIndex,
      count: sourceCount)
    return sourceCount
  }
}

extension Slice {
  @inlinable @inline(__always)
  public func initialize<Element>(
    fromContentsOf source: UnsafeMutableBufferPointer<Element>
  ) -> Index
  where Base == UnsafeMutableBufferPointer<Element>
  {
    let target = UnsafeMutableBufferPointer(rebasing: self)
    let i = target.initialize(fromContentsOf: source)
    return self.startIndex + i
  }

  @inlinable @inline(__always)
  public func initialize<Element>(
    fromContentsOf source: Slice<UnsafeMutableBufferPointer<Element>>
  ) -> Index
  where Base == UnsafeMutableBufferPointer<Element>
  {
    let target = UnsafeMutableBufferPointer(rebasing: self)
    let i = target.initialize(fromContentsOf: source)
    return self.startIndex + i
  }
}

extension UnsafeMutableBufferPointer {
  @inlinable @inline(__always)
  public func initializeAll<C: Collection>(
    fromContentsOf source: C
  ) where C.Element == Element {
    let i = self.initialize(fromContentsOf: source)
    assert(i == self.endIndex)
  }

  @inlinable @inline(__always)
  public func initializeAll(fromContentsOf source: Self) {
    let i = self.initialize(fromContentsOf: source)
    assert(i == self.endIndex)
  }

  @inlinable @inline(__always)
  public func initializeAll(fromContentsOf source: Slice<Self>) {
    let i = self.initialize(fromContentsOf: source)
    assert(i == self.endIndex)
  }

  @inlinable @inline(__always)
  public func moveInitializeAll(fromContentsOf source: Self) {
    let i = self.moveInitialize(fromContentsOf: source)
    assert(i == self.endIndex)
  }

  @inlinable @inline(__always)
  public func moveInitializeAll(fromContentsOf source: Slice<Self>) {
    let i = self.moveInitialize(fromContentsOf: source)
    assert(i == self.endIndex)
  }
}

extension Slice {
  @inlinable @inline(__always)
  public func initializeAll<C: Collection>(
    fromContentsOf source: C
  ) where Base == UnsafeMutableBufferPointer<C.Element> {
    let i = self.initialize(fromContentsOf: source)
    assert(i == self.endIndex)
  }

  @inlinable @inline(__always)
  public func initializeAll<Element>(
    fromContentsOf source: UnsafeMutableBufferPointer<Element>
  ) where Base == UnsafeMutableBufferPointer<Element> {
    let target = UnsafeMutableBufferPointer(rebasing: self)
    target.initializeAll(fromContentsOf: source)
  }

  @inlinable @inline(__always)
  public func initializeAll<Element>(
    fromContentsOf source: Slice<UnsafeMutableBufferPointer<Element>>
  ) where Base == UnsafeMutableBufferPointer<Element> {
    let target = UnsafeMutableBufferPointer(rebasing: self)
    target.initializeAll(fromContentsOf: source)
  }

  @inlinable @inline(__always)
  public func moveInitializeAll<Element>(
    fromContentsOf source: UnsafeMutableBufferPointer<Element>
  ) where Base == UnsafeMutableBufferPointer<Element> {
    let target = UnsafeMutableBufferPointer(rebasing: self)
    target.moveInitializeAll(fromContentsOf: source)
  }

  @inlinable @inline(__always)
  public func moveInitializeAll<Element>(
    fromContentsOf source: Slice<UnsafeMutableBufferPointer<Element>>
  ) where Base == UnsafeMutableBufferPointer<Element> {
    let target = UnsafeMutableBufferPointer(rebasing: self)
    target.moveInitializeAll(fromContentsOf: source)
  }
}

#if swift(<5.8)
extension UnsafeMutablePointer {
  @_alwaysEmitIntoClient
  public func update(repeating repeatedValue: Pointee, count: Int) {
    assert(count >= 0, "UnsafeMutablePointer.update(repeating:count:) with negative count")
    for i in 0 ..< count {
      self[i] = repeatedValue
    }
  }
}
#endif

extension Array {
  @inlinable
  internal static func _isWCSIABroken() -> Bool {
    #if _runtime(_ObjC)
    guard _isBridgedVerbatimToObjectiveC(Element.self) else {
      return false
    }
    #if os(macOS) || os(iOS) || os(watchOS) || os(tvOS)
    if #available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *) {
      return false
    }
    return true
    #else
    return false
    #endif

    #else
    return false
    #endif
  }
}

extension Sequence {
  @inlinable @inline(__always)
  public func _withContiguousStorageIfAvailable_SR14663<R>(
    _ body: (UnsafeBufferPointer<Element>) throws -> R
  ) rethrows -> R? {
    if Self.self == Array<Element>.self && Array<Element>._isWCSIABroken() {
      return nil
    }

    return try self.withContiguousStorageIfAvailable(body)
  }
}

extension Deque: Hashable where Element: Hashable {
  @inlinable
  public func hash(into hasher: inout Hasher) {
    hasher.combine(count)
    for element in self {
      hasher.combine(element)
    }
  }
}

extension Deque: Sequence {
  @frozen
  public struct Iterator: IteratorProtocol {
    @usableFromInline
    internal var _storage: Deque._Storage

    @usableFromInline
    internal var _nextSlot: _Slot

    @usableFromInline
    internal var _endSlot: _Slot

    @inlinable
    internal init(_storage: Deque._Storage, start: _Slot, end: _Slot) {
      self._storage = _storage
      self._nextSlot = start
      self._endSlot = end
    }

    @inlinable
    internal init(_base: Deque) {
      self = _base._storage.read { handle in
        let start = handle.startSlot
        let end = Swift.min(start.advanced(by: handle.count), handle.limSlot)
        return Self(_storage: _base._storage, start: start, end: end)
      }
    }

    @inlinable
    internal init(_base: Deque, from index: Int) {
      self = _base._storage.read { handle in
        assert(index >= 0 && index <= handle.count)
        let start = handle.slot(forOffset: index)
        if index == handle.count {
          return Self(_storage: _base._storage, start: start, end: start)
        }
        var end = handle.endSlot
        if start >= end { end = handle.limSlot }
        return Self(_storage: _base._storage, start: start, end: end)
      }
    }

    @inlinable
    @inline(never)
    internal mutating func _swapSegment() -> Bool {
      assert(_nextSlot == _endSlot)
      return _storage.read { handle in
        let end = handle.endSlot
        if end == .zero || end == _nextSlot {
          return false
        }
        _endSlot = end
        _nextSlot = .zero
        return true
      }
    }

    @inlinable
    public mutating func next() -> Element? {
      if _nextSlot == _endSlot {
        guard _swapSegment() else { return nil }
      }
      assert(_nextSlot < _endSlot)
      let slot = _nextSlot
      _nextSlot = _nextSlot.advanced(by: 1)
      return _storage.read { handle in
        return handle.ptr(at: slot).pointee
      }
    }
  }

  @inlinable
  public func makeIterator() -> Iterator {
    Iterator(_base: self)
  }

  @inlinable
  public __consuming func _copyToContiguousArray() -> ContiguousArray<Element> {
    ContiguousArray(unsafeUninitializedCapacity: _storage.count) { target, count in
      _storage.read { source in
        let segments = source.segments()
        let c = segments.first.count
        target[..<c].initializeAll(fromContentsOf: segments.first)
        count += segments.first.count
        if let second = segments.second {
          target[c ..< c + second.count].initializeAll(fromContentsOf: second)
          count += second.count
        }
        assert(count == source.count)
      }
    }
  }

  @inlinable
  public __consuming func _copyContents(
    initializing target: UnsafeMutableBufferPointer<Element>
  ) -> (Iterator, UnsafeMutableBufferPointer<Element>.Index) {
    _storage.read { source in
      let segments = source.segments()
      let c1 = Swift.min(segments.first.count, target.count)
      target[..<c1].initializeAll(fromContentsOf: segments.first.prefix(c1))
      guard target.count > c1, let second = segments.second else {
        return (Iterator(_base: self, from: c1), c1)
      }
      let c2 = Swift.min(second.count, target.count - c1)
      target[c1 ..< c1 + c2].initializeAll(fromContentsOf: second.prefix(c2))
      return (Iterator(_base: self, from: c1 + c2), c1 + c2)
    }
  }

  @inlinable
  public func withContiguousStorageIfAvailable<R>(
    _ body: (UnsafeBufferPointer<Element>) throws -> R
  ) rethrows -> R? {
    return try _storage.read { handle in
      let endSlot = handle.startSlot.advanced(by: handle.count)
      guard endSlot.position <= handle.capacity else { return nil }
      return try body(handle.buffer(for: handle.startSlot ..< endSlot))
    }
  }
}

#if swift(>=5.5)
extension Deque.Iterator: Sendable where Element: Sendable {}
#endif

extension Deque: RandomAccessCollection {
  public typealias Index = Int
  public typealias SubSequence = Slice<Self>
  public typealias Indices = Range<Int>

  @inlinable
  @inline(__always)
  public var count: Int { _storage.count }

  @inlinable
  @inline(__always)
  public var startIndex: Int { 0 }

  @inlinable
  @inline(__always)
  public var endIndex: Int { count }

  @inlinable
  @inline(__always)
  public var indices: Range<Int> { 0 ..< count }

  @inlinable
  @inline(__always)
  public func index(after i: Int) -> Int {
    return i + 1
  }

  @inlinable
  @inline(__always)
  public func formIndex(after i: inout Int) {
    i += 1
  }

  @inlinable
  @inline(__always)
  public func index(before i: Int) -> Int {
    return i - 1
  }

  @inlinable
  @inline(__always)
  public func formIndex(before i: inout Int) {
    i -= 1
  }

  @inlinable
  @inline(__always)
  public func index(_ i: Int, offsetBy distance: Int) -> Int {
    return i + distance
  }

  @inlinable
  public func index(
    _ i: Int,
    offsetBy distance: Int,
    limitedBy limit: Int
  ) -> Int? {
    let l = limit - i
    if distance > 0 ? l >= 0 && l < distance : l <= 0 && distance < l {
      return nil
    }
    return i + distance
  }

  @inlinable
  @inline(__always)
  public func distance(from start: Int, to end: Int) -> Int {
    return end - start
  }

  @inlinable
  public subscript(index: Int) -> Element {
    get {
      precondition(index >= 0 && index < count, "Index out of bounds")
      return _storage.read { $0.ptr(at: $0.slot(forOffset: index)).pointee }
    }
    set {
      precondition(index >= 0 && index < count, "Index out of bounds")
      _storage.ensureUnique()
      _storage.update { handle in
        let slot = handle.slot(forOffset: index)
        handle.ptr(at: slot).pointee = newValue
      }
    }
    @inline(__always)
    _modify {
      precondition(index >= 0 && index < count, "Index out of bounds")
      var (slot, value) = _prepareForModify(at: index)
      defer {
        _finalizeModify(slot, value)
      }
      yield &value
    }
  }

  @inlinable
  internal mutating func _prepareForModify(at index: Int) -> (_Slot, Element) {
    _storage.ensureUnique()
    return _storage.update { handle in
      let slot = handle.slot(forOffset: index)
      return (slot, handle.ptr(at: slot).move())
    }
  }

  @inlinable
  internal mutating func _finalizeModify(_ slot: _Slot, _ value: Element) {
    _storage.update { handle in
      handle.ptr(at: slot).initialize(to: value)
    }
  }

  @inlinable
  public subscript(bounds: Range<Int>) -> Slice<Self> {
    get {
      precondition(bounds.lowerBound >= 0 && bounds.upperBound <= count,
                   "Invalid bounds")
      return Slice(base: self, bounds: bounds)
    }
    set(source) {
      precondition(bounds.lowerBound >= 0 && bounds.upperBound <= count,
                   "Invalid bounds")
      self.replaceSubrange(bounds, with: source)
    }
  }
}

extension Deque: MutableCollection {
  @inlinable
  public mutating func swapAt(_ i: Int, _ j: Int) {
    precondition(i >= 0 && i < count, "Index out of bounds")
    precondition(j >= 0 && j < count, "Index out of bounds")
    _storage.ensureUnique()
    _storage.update { handle in
      let slot1 = handle.slot(forOffset: i)
      let slot2 = handle.slot(forOffset: j)
      handle.mutableBuffer.swapAt(slot1.position, slot2.position)
    }
  }

  @inlinable
  public mutating func withContiguousMutableStorageIfAvailable<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R
  ) rethrows -> R? {
    _storage.ensureUnique()
    return try _storage.update { handle in
      let endSlot = handle.startSlot.advanced(by: handle.count)
      guard endSlot.position <= handle.capacity else {
        return nil
      }
      let original = handle.mutableBuffer(for: handle.startSlot ..< endSlot)
      var extract = original
      defer {
        precondition(extract.baseAddress == original.baseAddress && extract.count == original.count,
                     "Closure must not replace the provided buffer")
      }
      return try body(&extract)
    }
  }

  @inlinable
  public mutating func _withUnsafeMutableBufferPointerIfSupported<R>(
    _ body: (inout UnsafeMutableBufferPointer<Element>) throws -> R
  ) rethrows -> R? {
    return try withContiguousMutableStorageIfAvailable(body)
  }
}

extension Deque: RangeReplaceableCollection {
  @inlinable
  public init() {
    _storage = _Storage()
  }

  @inlinable
  public mutating func reserveCapacity(_ minimumCapacity: Int) {
    _storage.ensureUnique(minimumCapacity: minimumCapacity, linearGrowth: true)
  }

  @inlinable
  public mutating func replaceSubrange<C: Collection>(
    _ subrange: Range<Int>,
    with newElements: __owned C
  ) where C.Element == Element {
    precondition(subrange.lowerBound >= 0 && subrange.upperBound <= count, "Index range out of bounds")
    let removalCount = subrange.count
    let insertionCount = newElements.count
    let deltaCount = insertionCount - removalCount
    _storage.ensureUnique(minimumCapacity: count + deltaCount)

    let replacementCount = Swift.min(removalCount, insertionCount)
    let targetCut = subrange.lowerBound + replacementCount
    let sourceCut = newElements.index(newElements.startIndex, offsetBy: replacementCount)

    _storage.update { target in
      target.uncheckedReplaceInPlace(
        inOffsets: subrange.lowerBound ..< targetCut,
        with: newElements[..<sourceCut])
      if deltaCount < 0 {
        let r = targetCut ..< subrange.upperBound
        assert(replacementCount + r.count == removalCount)
        target.uncheckedRemove(offsets: r)
      } else if deltaCount > 0 {
        target.uncheckedInsert(
          contentsOf: newElements[sourceCut...],
          count: deltaCount,
          atOffset: targetCut)
      }
    }
  }

  @inlinable
  public init(repeating repeatedValue: Element, count: Int) {
    precondition(count >= 0)
    self.init(minimumCapacity: count)
    _storage.update { handle in
      assert(handle.startSlot == .zero)
      if count > 0 {
        handle.ptr(at: .zero).initialize(repeating: repeatedValue, count: count)
      }
      handle.count = count
    }
  }

  @inlinable
  public init<S: Sequence>(_ elements: S) where S.Element == Element {
    self.init()
    self.append(contentsOf: elements)
  }

  @inlinable
  public init<C: Collection>(_ elements: C) where C.Element == Element {
    let c = elements.count
    guard c > 0 else { _storage = _Storage(); return }
    self._storage = _Storage(minimumCapacity: c)
    _storage.update { handle in
      assert(handle.startSlot == .zero)
      let target = handle.mutableBuffer(for: .zero ..< _Slot(at: c))
      let done: Void? = elements._withContiguousStorageIfAvailable_SR14663 { source in
        target.initializeAll(fromContentsOf: source)
      }
      if done == nil {
        target.initializeAll(fromContentsOf: elements)
      }
      handle.count = c
    }
  }

  @inlinable
  public mutating func append(_ newElement: Element) {
    _storage.ensureUnique(minimumCapacity: count + 1)
    _storage.update {
      $0.uncheckedAppend(newElement)
    }
  }

  @inlinable
  public mutating func append<S: Sequence>(contentsOf newElements: S) where S.Element == Element {
    let done: Void? = newElements._withContiguousStorageIfAvailable_SR14663 { source in
      _storage.ensureUnique(minimumCapacity: count + source.count)
      _storage.update { $0.uncheckedAppend(contentsOf: source) }
    }
    if done != nil {
      return
    }

    let underestimatedCount = newElements.underestimatedCount
    _storage.ensureUnique(minimumCapacity: count + underestimatedCount)
    var it: S.Iterator = _storage.update { target in
      let gaps = target.availableSegments()
      let (it, copied) = gaps.initialize(fromSequencePrefix: newElements)
      target.count += copied
      return it
    }
    while let next = it.next() {
      _storage.ensureUnique(minimumCapacity: count + 1)
      _storage.update { target in
        target.uncheckedAppend(next)
        let gaps = target.availableSegments()
        target.count += gaps.initialize(fromPrefixOf: &it)
      }
    }
  }

  @inlinable
  public mutating func append<C: Collection>(contentsOf newElements: C) where C.Element == Element {
    let done: Void? = newElements._withContiguousStorageIfAvailable_SR14663 { source in
      _storage.ensureUnique(minimumCapacity: count + source.count)
      _storage.update { $0.uncheckedAppend(contentsOf: source) }
    }
    guard done == nil else { return }

    let c = newElements.count
    guard c > 0 else { return }
    _storage.ensureUnique(minimumCapacity: count + c)
    _storage.update { target in
      let gaps = target.availableSegments().prefix(c)
      gaps.initialize(from: newElements)
      target.count += c
    }
  }

  @inlinable
  public mutating func insert(_ newElement: Element, at index: Int) {
    precondition(index >= 0 && index <= count,
                 "Can't insert element at invalid index")
    _storage.ensureUnique(minimumCapacity: count + 1)
    _storage.update { target in
      if index == 0 {
        target.uncheckedPrepend(newElement)
        return
      }
      if index == count {
        target.uncheckedAppend(newElement)
        return
      }
      let gap = target.openGap(ofSize: 1, atOffset: index)
      assert(gap.first.count == 1)
      gap.first.baseAddress!.initialize(to: newElement)
    }
  }

  @inlinable
  public mutating func insert<C: Collection>(
    contentsOf newElements: __owned C, at index: Int
  ) where C.Element == Element {
    precondition(index >= 0 && index <= count,
                 "Can't insert elements at an invalid index")
    let newCount = newElements.count
    _storage.ensureUnique(minimumCapacity: count + newCount)
    _storage.update { target in
      target.uncheckedInsert(contentsOf: newElements, count: newCount, atOffset: index)
    }
  }

  @inlinable
  @discardableResult
  public mutating func remove(at index: Int) -> Element {
    precondition(index >= 0 && index < self.count, "Index out of bounds")
    _storage.ensureUnique()
    return _storage.update { target in
      let result = self[index]
      target.uncheckedRemove(offsets: index ..< index + 1)
      return result
    }
  }

  @inlinable
  public mutating func removeSubrange(_ bounds: Range<Int>) {
    precondition(bounds.lowerBound >= 0 && bounds.upperBound <= self.count,
                 "Index range out of bounds")
    _storage.ensureUnique()
    _storage.update { $0.uncheckedRemove(offsets: bounds) }
  }

  @inlinable
  public mutating func _customRemoveLast() -> Element? {
    precondition(!isEmpty, "Cannot remove last element of an empty Deque")
    _storage.ensureUnique()
    return _storage.update { $0.uncheckedRemoveLast() }
  }

  @inlinable
  public mutating func _customRemoveLast(_ n: Int) -> Bool {
    precondition(n >= 0, "Can't remove a negative number of elements")
    precondition(n <= count, "Can't remove more elements than there are in the Collection")
    _storage.ensureUnique()
    _storage.update { $0.uncheckedRemoveLast(n) }
    return true
  }

  @inlinable
  @discardableResult
  public mutating func removeFirst() -> Element {
    precondition(!isEmpty, "Cannot remove first element of an empty Deque")
    _storage.ensureUnique()
    return _storage.update { $0.uncheckedRemoveFirst() }
  }

  @inlinable
  public mutating func removeFirst(_ n: Int) {
    precondition(n >= 0, "Can't remove a negative number of elements")
    precondition(n <= count, "Can't remove more elements than there are in the Collection")
    _storage.ensureUnique()
    return _storage.update { $0.uncheckedRemoveFirst(n) }
  }

  @inlinable
  public mutating func removeAll(keepingCapacity keepCapacity: Bool = false) {
    if keepCapacity {
      _storage.ensureUnique()
      _storage.update { $0.uncheckedRemoveAll() }
    } else {
      self = Deque()
    }
  }
}

extension Deque: Equatable where Element: Equatable {
  @inlinable
  public static func ==(left: Self, right: Self) -> Bool {
    return left.elementsEqual(right)
  }
}

#if swift(>=5.5)
extension Deque: @unchecked Sendable where Element: Sendable {}
#endif

extension Deque: ExpressibleByArrayLiteral {
  @inlinable
  @inline(__always)
  public init(arrayLiteral elements: Element...) {
    self.init(elements)
  }
}

extension Deque: CustomStringConvertible {
  public var description: String {
    _arrayDescription(for: self)
  }
}

extension Deque: CustomDebugStringConvertible {
  public var debugDescription: String {
    _arrayDescription(
      for: self, debug: true, typeName: "Deque<\(Element.self)>")
  }
}

@inlinable
public func _arrayDescription<C: Collection>(
  for elements: C,
  debug: Bool = false,
  typeName: String? = nil
) -> String {
  var result = ""
  if let typeName = typeName {
    result += "\(typeName)("
  }
  result += "["
  var first = true
  for item in elements {
    if first {
      first = false
    } else {
      result += ", "
    }
    if debug {
      debugPrint(item, terminator: "", to: &result)
    } else {
      print(item, terminator: "", to: &result)
    }
  }
  result += "]"
  if typeName != nil { result += ")" }
  return result
}

extension Deque: CustomReflectable {
  public var customMirror: Mirror {
    Mirror(self, unlabeledChildren: self, displayStyle: .collection)
  }
}

extension Deque {
  @inlinable
  public init(
    unsafeUninitializedCapacity capacity: Int,
    initializingWith initializer:
      (inout UnsafeMutableBufferPointer<Element>, inout Int) throws -> Void
  ) rethrows {
    self._storage = .init(minimumCapacity: capacity)
    try _storage.update { handle in
      handle.startSlot = .zero
      var count = 0
      var buffer = handle.mutableBuffer(for: .zero ..< _Slot(at: capacity))
      defer {
        precondition(count <= capacity,
          "Initialized count set to greater than specified capacity")
        let b = handle.mutableBuffer(for: .zero ..< _Slot(at: capacity))
        precondition(buffer.baseAddress == b.baseAddress && buffer.count == b.count,
          "Initializer relocated Deque storage")
        handle.count = count
      }
      try initializer(&buffer, &count)
    }
  }
}

extension Deque {
  @inlinable
  public mutating func popFirst() -> Element? {
    guard count > 0 else { return nil }
    _storage.ensureUnique()
    return _storage.update {
      $0.uncheckedRemoveFirst()
    }
  }

  @inlinable
  public mutating func prepend(_ newElement: Element) {
    _storage.ensureUnique(minimumCapacity: count + 1)
    return _storage.update {
      $0.uncheckedPrepend(newElement)
    }
  }

  @inlinable
  public mutating func prepend<C: Collection>(contentsOf newElements: C) where C.Element == Element {
    let done: Void? = newElements._withContiguousStorageIfAvailable_SR14663 { source in
      _storage.ensureUnique(minimumCapacity: count + source.count)
      _storage.update { $0.uncheckedPrepend(contentsOf: source) }
    }
    guard done == nil else { return }

    let c = newElements.count
    guard c > 0 else { return }
    _storage.ensureUnique(minimumCapacity: count + c)
    _storage.update { target in
      let gaps = target.availableSegments().suffix(c)
      gaps.initialize(from: newElements)
      target.count += c
      target.startSlot = target.slot(target.startSlot, offsetBy: -c)
    }
  }

  @inlinable
  public mutating func prepend<S: Sequence>(contentsOf newElements: S) where S.Element == Element {
    let done: Void? = newElements._withContiguousStorageIfAvailable_SR14663 { source in
      _storage.ensureUnique(minimumCapacity: count + source.count)
      _storage.update { $0.uncheckedPrepend(contentsOf: source) }
    }
    guard done == nil else { return }

    let originalCount = self.count
    self.append(contentsOf: newElements)
    let newCount = self.count
    let c = newCount - originalCount
    _storage.update { target in
      target.startSlot = target.slot(forOffset: originalCount)
      target.count = target.capacity
      target.closeGap(offsets: c ..< c + (target.capacity - newCount))
      assert(target.count == newCount)
    }
  }
}
