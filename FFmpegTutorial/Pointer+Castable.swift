//
// Reference:
// https://gist.github.com/codelynx/83c7bc12e1f8b3e1e9757640a3ba29e8
// https://github.com/oozoofrog/Castable/blob/master/Castable/Castable.swift
//
// Swift Pointer casting & get pointer from array
//
//    let array1 = [1, 2, 3, 4]
//    let array1Ptr = array1.pointer
//    let array1BufferPtr = array1.bufferPointer
//    print("array1: \(array1)")
//    print("array1 array1.pointer: \(type(of: array1Ptr)), address: \(array1Ptr)")
//    print("array1 array1.bufferPointer: \(type(of: array1BufferPtr)), address: \(array1BufferPtr)")
//
//    let array1Slice = array1[1...2]
//    let array1SlicePtr = array1Slice.pointer
//    let array1SliceBPtr = array1Slice.bufferPointer
//    print("array1[1...2]: \(array1Slice)")
//    print("array1[1...2] array1[1...2].pointer: \(type(of: array1SlicePtr)), address: \(array1SlicePtr)")
//    print("array1[1...2] array1[1...2].bufferPointer: \(type(of: array1SliceBPtr)), address: \(array1SliceBPtr)")
//
//    let array1MutablePtr: UnsafeMutablePointer<Int> = array1Ptr.cast()
//    array1MutablePtr.pointee = 10
//    print("\(array1)") // 1 -> 10 changed
//
//    let _: UnsafeRawPointer = array1BufferPtr.cast()
//    let _: UnsafeMutableRawPointer = array1BufferPtr.cast()
//    let _: UnsafePointer<Int> = array1BufferPtr.cast()
//    //let _: UnsafePointer<UInt8> = array1BufferPtr.cast() // Complie error
//    let _: UnsafeMutablePointer<Int> = array1BufferPtr.cast()
//    let array1RawBufferPtr: UnsafeRawBufferPointer = array1BufferPtr.cast()
//    let _: UnsafeMutableRawPointer = array1BufferPtr.cast()
//    let _: UnsafeMutableBufferPointer = array1BufferPtr.cast()
//    let _: Array = array1BufferPtr.cast()
//    let _: ArraySlice = array1BufferPtr.cast()
//
//    let _: UnsafeRawPointer = array1RawBufferPtr.cast()
//    let _: UnsafeMutableRawPointer = array1RawBufferPtr.cast()
//    let array1UInt8Ptr: UnsafePointer<UInt8> = array1RawBufferPtr.cast()
//    let _: UnsafeMutablePointer<UInt8> = array1RawBufferPtr.cast()
//    let _: UnsafeMutableRawBufferPointer = array1RawBufferPtr.cast()
//    print(array1UInt8Ptr)

import Foundation

extension UnsafeRawPointer {
    func cast() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: self)
    }
    
    func cast<T>() -> UnsafePointer<T> {
        return self.assumingMemoryBound(to: T.self)
    }
    
    func cast<T>() -> UnsafeMutablePointer<T> {
        return UnsafeMutablePointer(mutating: cast())
    }
    
    func cast() -> OpaquePointer {
        return OpaquePointer(self)
    }
}

extension UnsafeMutableRawPointer {
    func cast() -> UnsafeRawPointer {
        return UnsafeRawPointer(self)
    }
    
    func cast<T>() -> UnsafePointer<T> {
        return UnsafePointer(self.assumingMemoryBound(to: T.self))
    }
    
    func cast<T>() -> UnsafeMutablePointer<T> {
        return self.assumingMemoryBound(to: T.self)
    }
    
    func cast() -> OpaquePointer {
        return OpaquePointer(self)
    }
}

extension UnsafePointer {
    func cast() -> UnsafeRawPointer {
        return UnsafeRawPointer(self)
    }
    
    func cast() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: self)
    }
    
    func cast() -> UnsafeMutablePointer<Pointee> {
        return UnsafeMutablePointer(mutating: self)
    }
    
    func cast() -> OpaquePointer {
        return OpaquePointer(self)
    }
}

extension UnsafeMutablePointer {
    func cast() -> UnsafeRawPointer {
        return UnsafeRawPointer(self)
    }
    
    func cast() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(self)
    }
    
    func cast() -> UnsafePointer<Pointee> {
        return UnsafePointer(self)
    }
    
    func cast() -> OpaquePointer {
        return OpaquePointer(self)
    }
}

extension UnsafeRawBufferPointer {
    func cast() -> UnsafeRawPointer {
        return self.baseAddress!
    }
    
    func cast() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: cast())
    }
    
    func cast<T>() -> UnsafePointer<T> {
        return self.baseAddress!.assumingMemoryBound(to: T.self)
    }
    
    func cast<T>() -> UnsafeMutablePointer<T> {
        return UnsafeMutablePointer(mutating: cast())
    }
    
    func cast() -> UnsafeMutableRawBufferPointer {
        return UnsafeMutableRawBufferPointer(mutating: self)
    }
    
    func cast() -> OpaquePointer {
        return OpaquePointer(self.baseAddress!)
    }
}

extension UnsafeMutableRawBufferPointer {
    func cast() -> UnsafeRawPointer {
        return UnsafeRawPointer(self.baseAddress!)
    }
    
    func cast() -> UnsafeMutableRawPointer {
        return self.baseAddress!
    }
    
    func cast<T>() -> UnsafePointer<T> {
        return UnsafePointer(self.baseAddress!.assumingMemoryBound(to: T.self))
    }
    
    func cast<T>() -> UnsafeMutablePointer<T> {
        return self.baseAddress!.assumingMemoryBound(to: T.self)
    }
    
    func cast() -> UnsafeRawBufferPointer {
        return UnsafeRawBufferPointer(self)
    }
    
    func cast() -> OpaquePointer {
        return OpaquePointer(self.baseAddress!)
    }
}

extension UnsafeBufferPointer {
    func cast() -> UnsafeRawPointer {
        return UnsafeRawPointer(self.baseAddress!)
    }
    
    func cast() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: self.baseAddress!)
    }
    
    func cast() -> UnsafePointer<Element> {
        return UnsafePointer(self.baseAddress!)
    }
    
    func cast() -> UnsafeMutablePointer<Element> {
        return UnsafeMutablePointer(mutating: self.baseAddress!)
    }
    
    func cast() -> UnsafeRawBufferPointer {
        return UnsafeRawBufferPointer(self)
    }
    
    func cast() -> UnsafeMutableRawBufferPointer {
        return UnsafeMutableRawBufferPointer(mutating: cast())
    }
    
    func cast() -> UnsafeMutableBufferPointer<Element> {
        return UnsafeMutableBufferPointer(mutating: self)
    }
    
    func cast() -> Array<Element> {
        return Array(self)
    }
    
    func cast() -> ArraySlice<Element> {
        return ArraySlice(self)
    }
    
    func cast() -> OpaquePointer {
        return OpaquePointer(self.baseAddress!)
    }
}

extension OpaquePointer {
    func cast() -> UnsafeRawPointer {
        return UnsafeRawPointer(self)
    }
    
    func cast() -> UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(self)
    }
    
    func cast<T>() -> UnsafePointer<T> {
        return UnsafePointer(self)
    }
    
    func cast<T>() -> UnsafeMutablePointer<T> {
        return UnsafeMutablePointer(self)
    }
}



protocol Pointerable {
    associatedtype Element
    var pointer: UnsafePointer<Element> {get}
    var bufferPointer: UnsafeBufferPointer<Element> {get}
}

extension Array : Pointerable {
    var pointer: UnsafePointer<Element> {
        return UnsafePointer<Element>(self)
    }
    
    var bufferPointer: UnsafeBufferPointer<Element> {
        return self.withUnsafeBufferPointer { $0 }
    }
}

extension ArraySlice : Pointerable {
    var pointer: UnsafePointer<Element> {
        return self.withUnsafeBufferPointer { $0.baseAddress! }
    }
    
    var bufferPointer: UnsafeBufferPointer<Element> {
        return self.withUnsafeBufferPointer { $0 }
    }
}
