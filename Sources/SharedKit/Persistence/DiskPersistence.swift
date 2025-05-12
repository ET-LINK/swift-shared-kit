import Foundation

public class DiskPersistence: Persistence {
    public static var shared = DiskPersistence()
    
    // 序列化队列
    private let serialQueue = DispatchQueue(label: "com.app.persistence.serial")
    // 最后保存时间
    private var lastSaveTime: [String: Date] = [:]
    // 最小保存间隔（秒）
    private let minSaveInterval: TimeInterval = 1.0
    // 防抖定时器映射
    private var debounceTimers: [String: Timer] = [:]
    
    private var documents: URL? {
        try? FileManager.default.url(for: .documentDirectory,
                                   in: .userDomainMask,
                                   appropriateFor: nil,
                                   create: false)
    }
    
    init() {}
    
    // MARK: - Public Methods
    
    public func load<T: Codable>(objects filename: String) async throws -> [T] {
        guard let url = documents?.appendingPathComponent(filename, isDirectory: false),
              FileManager.default.fileExists(atPath: url.path) else {
            return []
        }
        
        return try await serialQueue.asyncAndThrow {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([T].self, from: data)
        }
    }
    
    public func load<T: Codable>(object filename: String) async throws -> T? {
        guard let url = documents?.appendingPathComponent(filename, isDirectory: false),
              FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        
        return try await serialQueue.asyncAndThrow {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        }
    }
    
    public func save<T: Codable>(filename: String, objects: [T]) async throws {
        // 检查是否需要延迟写入
        let now = Date()
        if let lastSave = lastSaveTime[filename],
           now.timeIntervalSince(lastSave) < minSaveInterval {
            // 使用防抖写入
            await debounceSave(filename: filename, object: objects)
            return
        }
        
        // 执行立即保存
        try await performSave(filename: filename, object: objects)
    }
    
    public func save<T: Codable>(filename: String, object: T) async throws {
        // 检查是否需要延迟写入
        let now = Date()
        if let lastSave = lastSaveTime[filename],
           now.timeIntervalSince(lastSave) < minSaveInterval {
            // 使用防抖写入
            await debounceSave(filename: filename, object: object)
            return
        }
        
        // 执行立即保存
        try await performSave(filename: filename, object: object)
    }
    
    public func delete(filename: String) throws {
        // 清理保存状态
        lastSaveTime.removeValue(forKey: filename)
        // 取消定时器
        debounceTimers[filename]?.invalidate()
        debounceTimers.removeValue(forKey: filename)
        
        guard let url = documents?.appendingPathComponent(filename, isDirectory: false) else {
            return
        }
        try FileManager.default.removeItem(at: url)
    }
    
    public func deleteAll() throws {
        // 清理所有状态
        lastSaveTime.removeAll()
        // 清除所有定时器
        debounceTimers.forEach { $0.value.invalidate() }
        debounceTimers.removeAll()
        
        guard let documents else { return }
        let files = try FileManager.default.contentsOfDirectory(at: documents, includingPropertiesForKeys: nil)
        for url in files {
            try FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Private Methods
    
    private func debounceSave<T: Codable>(filename: String, object: T) async {
        await MainActor.run {
            // 取消现有的定时器
            debounceTimers[filename]?.invalidate()
            
            // 创建新的定时器
            let timer = Timer.scheduledTimer(withTimeInterval: minSaveInterval, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                
                Task {
                    do {
                        try await self.performSave(filename: filename, object: object)
                    } catch {
                        print("Error in debounced save: \(error)")
                    }
                }
                self.debounceTimers.removeValue(forKey: filename)
            }
            
            debounceTimers[filename] = timer
        }
    }
    
    private func performSave<T: Codable>(filename: String, object: T) async throws {
        guard let url = documents?.appendingPathComponent(filename, isDirectory: false) else {
            return
        }
        
        try await serialQueue.asyncAndThrow { [weak self] in
            let data = try JSONEncoder().encode(object)
            try data.write(to: url)
            self?.lastSaveTime[filename] = Date()
        }
    }
}

// MARK: - DispatchQueue Extension
extension DispatchQueue {
    func asyncAndThrow<T>(_ block: @escaping () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            async {
                do {
                    let result = try block()
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
