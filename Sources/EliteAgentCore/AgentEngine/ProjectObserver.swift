import Foundation

@MainActor
public protocol ProjectObserverDelegate: AnyObject {
    func projectDidDetectChange(at path: String, flags: FSEventStreamEventFlags)
}

public final class ProjectObserver: @unchecked Sendable {
    private let path: String
    private var stream: FSEventStreamRef?
    private weak var delegate: ProjectObserverDelegate?
    
    public init(path: String, delegate: ProjectObserverDelegate) {
        self.path = path
        self.delegate = delegate
    }
    
    public func start() {
        var context = FSEventStreamContext(
            version: 0, 
            info: Unmanaged.passUnretained(self).toOpaque(), 
            retain: nil, 
            release: nil, 
            copyDescription: nil
        )
        
        let callback: FSEventStreamCallback = { (streamRef, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds) in
            let observer = Unmanaged<ProjectObserver>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
            let paths = eventPaths.assumingMemoryBound(to: UnsafePointer<Int8>.self)
            
            for i in 0..<numEvents {
                let path = String(cString: paths[i])
                let flags = eventFlags[i]
                Task { @MainActor in
                    observer.delegate?.projectDidDetectChange(at: path, flags: flags)
                }
            }
        }
        
        let pathsToWatch = [path] as CFArray
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        
        self.stream = FSEventStreamCreate(
            nil, 
            callback, 
            &context, 
            pathsToWatch, 
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 
            1.0, 
            flags
        )
        
        guard let stream = stream else { return }
        // FSEventStreamSetDispatchQueue is an Apple system API boundary that requires a DispatchQueue.
        // The callback bridges into Swift Concurrency via Task { @MainActor in ... } inside the handler.
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }
    
    public func stop() {
        guard let stream = stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
    
    deinit {
        stop()
    }
}
