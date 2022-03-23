import ArgumentParser
import Foundation
import SwiftShell
import Alamofire
import SwiftyJSON

@main
struct JVCL: ParsableCommand {
    func run() throws {
        /// 获取构建的分支
        let branch = try getEnvironment(name: "BRANCH")
        /// 获取是否有自定义的changeLog 不为空就不用获取了
        if let changelog = ProcessInfo.processInfo.environment["GIT_LOG"],
            !changelog.isEmpty {
            try saveLogToFile(logContent: changelog, branch: branch)
            return
        }
        /// 获取打包类型
        let mode = try getEnvironment(name: "MODE")
        /// 获取打包版本
        let version = try getEnvironment(name: "BUILD_NAME")
        
        /// 获取当前 build ID
        let buildId = try getEnvironment(name: "BUILD_ID")
        guard var id = UInt(buildId) else {
            print("BUILD_ID 不是整数")
            throw ExitCode.failure
        }
        
        if let commit = ProcessInfo.processInfo.environment["LAST_BUILD_COMMIT"] {
            try loadGitLog(lastBuildCommit: commit, branch: branch)
        } else {
            var jobDetail:JobDetail?
            var jobs:[JobDetail] = []
            let minId = id - 20;
            while id > 0 {
                defer {
                    id -= 1
                }
                guard id >= minId else {
                    break
                }
                guard let detail = try getJobDetail(buildId: id) else {
                    continue
                }
                jobs.append(detail)
                guard detail.isSuccess else {continue}
                guard branch == detail.branch else {continue}
                guard mode == detail.model else {continue}
                guard version >= detail.version else {continue}
                jobDetail = detail
                break
            }
            guard let jobDetail = jobDetail else {
                return
            }
            try loadGitLog(lastBuildCommit: jobDetail.gitCommit, branch: branch)
        }
    }
    
    func loadGitLog(lastBuildCommit:String, branch:String) throws {
        let workspace = try getEnvironment(name: "WORKSPACE")
        SwiftShell.main.currentdirectory = workspace
        /// 获取打包的 Git 提交
        let gitCommit = try getEnvironment(name: "GIT_COMMIT")
        let command = runAsync("git", "log", "\(lastBuildCommit)..\(gitCommit)")
        try command.finish()
        let commandStdio = command.stdout.read()
        var logContent:String = ""
        commandStdio.components(separatedBy: "\n\n").forEach { content in
            guard !content.contains("commit") else {return}
            logContent += """
            \(content.replacingOccurrences(of: "    ", with: ""))
            
            """
        }
        try saveLogToFile(logContent: logContent, branch: branch)
    }
    
    func saveLogToFile(logContent:String, branch:String) throws {
        var logContent = logContent
        guard !logContent.isEmpty else {
            throw ExitCode.failure
        }
        if !branch.isEmpty {
            logContent = """
            代码分支: \(branch)
            
            \(logContent)
            """
        }
        guard let data = logContent.data(using: .utf8) else {
            throw ExitCode.failure
        }
        let pwd = try getEnvironment(name: "PWD")
        let logFile = "\(pwd)/git.log"
        var isDirectory = ObjCBool(false)
        if FileManager.default.fileExists(atPath: logFile,
                                          isDirectory: &isDirectory),
           !isDirectory.boolValue {
            print("\(logFile)已经存在，删除之前的旧日志")
            /// 删除之前的文件
            try FileManager.default.removeItem(atPath: logFile)
        }
        print(pwd)
        guard FileManager.default.createFile(atPath: logFile,
                                             contents: data,
                                             attributes: nil) else {
            print("创建git.log失败")
            throw ExitCode.failure
        }
    }

    private func getEnvironment(name:String) throws -> String {
        guard let value = ProcessInfo.processInfo.environment[name] else {
            print("变量 \(name) 在环境不存在")
            throw ExitCode.failure
        }
        return value
    }
    
    /// 获取 JOB 的详情
    private func getJobDetail(buildId:UInt) throws -> JobDetail? {
        let buildUrl = try buildUrl(with: buildId)
        print(buildUrl)
        let semaphore = DispatchSemaphore(value: 0)
        let userName = try getEnvironment(name: "JENKINS_USERNAME")
        let password = try getEnvironment(name: "JENKINS_PASSWORD")
        let headers:HTTPHeaders = [.authorization(username: userName,
                                                  password: password)]
        var detail:JobDetail?
        AF.request(buildUrl, headers: headers)
            .responseString(queue: DispatchQueue.global()) { response in
                defer {
                    semaphore.signal()
                }
                guard let jsonString = response.value else {return}
                let json = JSON(parseJSON: jsonString)
                guard json.type != .null else {return}
                guard let result = json["result"].string else {return}
                let isSuccess = result == "SUCCESS"
                let actions = json["actions"].arrayValue
                guard !actions.isEmpty else {return}
                var version:String?
                var mode:String?
                var branch:String?
                var gitCommit:String?
                actions.forEach { json in
                    guard let className = json["_class"].string else {return}
                    if className == "hudson.model.ParametersAction" {
                        let parameters = json["parameters"].arrayValue
                        parameters.forEach { json in
                            guard let name = json["name"].string else {return}
                            let value = json["value"].string
                            if name == "BRANCH" {
                                branch = value
                            } else if name == "MODE" {
                                mode = value
                            } else if name == "BUILD_NAME" {
                                version = value
                            }
                        }
                    } else if className == "hudson.plugins.git.util.BuildData" {
                        gitCommit = json["lastBuiltRevision"].dictionaryValue["SHA1"]?.string
                    }
                }
                guard let version = version else {
                    return
                }
                guard let mode = mode else {
                    return
                }
                guard let branch = branch else {
                    return
                }
                guard let gitCommit = gitCommit else {
                    return
                }
                detail = JobDetail(id: buildId,
                                   branch: branch,
                                   model: mode,
                                   version: version,
                                   gitCommit: gitCommit,
                                   isSuccess: isSuccess)
            }
        semaphore.wait()
        return detail
    }
    
    private func buildUrl(with id:UInt) throws -> String {
        /// 获取当前 Job 地址
        let jobUrl = try getEnvironment(name: "JOB_URL")
        return "\(jobUrl)\(id)/api/json?pretty=true"
    }
}

struct JobDetail {
    let id:UInt
    /// 分支
    let branch:String
    /// 类型
    let model:String
    /// 包名
    let version:String
    /// Git 提交
    let gitCommit:String
    /// 是否成功
    let isSuccess:Bool
}
