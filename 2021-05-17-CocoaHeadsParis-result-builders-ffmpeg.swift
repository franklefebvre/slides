/**
 CocoaHeads Paris, May 2021
 
 Swift Result Builders & FFmpeg
 Frank Lefebvre
 
 Slides can be downloaded here:
 https://github.com/franklefebvre/slides/blob/master/2021-05-17-CocoaHeadsParis-result-builders-ffmpeg.pdf
 */

import Foundation

struct VideoBuildingBlock {
    enum Component {
        case resource(file: String)
        case hstack(components: [VideoBuildingBlock])
        case vstack(components: [VideoBuildingBlock])
        case zstack(components: [VideoBuildingBlock])
    }
    var contents: Component
    var offset: CGPoint = .zero
}

protocol VideoComponentConvertible {
    func makeVideoComponents() -> [VideoBuildingBlock]
}

extension VideoBuildingBlock: VideoComponentConvertible {
    func makeVideoComponents() -> [VideoBuildingBlock] {
        [self]
    }
}

extension Array: VideoComponentConvertible where Element: VideoComponentConvertible {
    func makeVideoComponents() -> [VideoBuildingBlock] {
        flatMap { $0.makeVideoComponents() }
    }
}

@resultBuilder
struct VideoComposer {
    static func buildBlock(_ components: [VideoBuildingBlock]...) -> [VideoBuildingBlock] {
        components.flatMap { $0 }
    }
    
    static func buildOptional(_ component: [VideoBuildingBlock]?) -> [VideoBuildingBlock] {
        component ?? []
    }
    
    static func buildEither(first component: [VideoBuildingBlock]) -> [VideoBuildingBlock] {
        component
    }
    
    static func buildEither(second component: [VideoBuildingBlock]) -> [VideoBuildingBlock] {
        component
    }
    
    static func buildArray(_ components: [[VideoBuildingBlock]]) -> [VideoBuildingBlock] {
        components.flatMap { $0 }
    }
    
    static func buildExpression(_ expression: VideoComponentConvertible) -> [VideoBuildingBlock] {
        expression.makeVideoComponents()
    }
}

struct Resource: VideoComponentConvertible {
    let file: String
    let offset: CGPoint
    init(_ file: String, offset: CGPoint = .zero) {
        self.file = file
        self.offset = offset
    }
    func makeVideoComponents() -> [VideoBuildingBlock] {
        [VideoBuildingBlock(contents: .resource(file: file), offset: offset)]
    }
}

struct HStack: VideoComponentConvertible {
    let content: () -> [VideoBuildingBlock]
    init(offset: CGPoint = .zero, @VideoComposer content: @escaping () -> [VideoBuildingBlock]) {
        self.content = content
    }
    func makeVideoComponents() -> [VideoBuildingBlock] {
        [VideoBuildingBlock(contents: .hstack(components: content()))]
    }
}

struct VStack: VideoComponentConvertible {
    let content: () -> [VideoBuildingBlock]
    init(@VideoComposer content: @escaping () -> [VideoBuildingBlock]) {
        self.content = content
    }
    func makeVideoComponents() -> [VideoBuildingBlock] {
        [VideoBuildingBlock(contents: .vstack(components: content()))]
    }
}

struct ZStack: VideoComponentConvertible {
    let content: () -> [VideoBuildingBlock]
    init(@VideoComposer content: @escaping () -> [VideoBuildingBlock]) {
        self.content = content
    }
    func makeVideoComponents() -> [VideoBuildingBlock] {
        [VideoBuildingBlock(contents: .zstack(components: content()))]
    }
}

protocol Video: VideoComponentConvertible {
    @VideoComposer var body: [VideoBuildingBlock] { get }
}

extension Video {
    func makeVideoComponents() -> [VideoBuildingBlock] {
        body
    }
}

extension VideoBuildingBlock {
    var fileName: String {
        guard case .resource(let file) = contents else {
            return ""
        }
        return file
    }
}

extension Array where Element == VideoBuildingBlock {
    
    func ffmpegArgs() -> [String] {
        var inputs = [VideoBuildingBlock]()
        var streams = [String]()
        
        func visit(_ node: VideoBuildingBlock) -> String {
            switch node.contents {
            case .resource(_):
                let output = "\(inputs.count)"
                inputs.append(node)
                return output
            case .hstack(let components):
                return appendHVStack(command: "hstack", components: components)
            case .vstack(let components):
                return appendHVStack(command: "vstack", components: components)
            case .zstack(let components):
                return appendZStack(components: components)
            }
        }
        
        func appendHVStack(command: String, components: [VideoBuildingBlock]) -> String {
            var children = [String]()
            for component in components {
                children.append(visit(component))
            }
            let output = "s\(streams.count)"
            let input = children.map {"[\($0)]"}.joined()
            streams.append("\(input)\(command)=inputs=\(children.count)[\(output)]")
            return output
        }
        
        func appendZStack(components: [VideoBuildingBlock]) -> String {
            guard let first = components.first else {
                return ""
            }
            var main = visit(first)
            var output = main
            for component in components.dropFirst() {
                let overlay = visit(component)
                output = "s\(streams.count)"
                streams.append("[\(main)][\(overlay)]overlay=\(component.offset.x):\(component.offset.y)[\(output)]")
                main = output
            }
            return output
        }
        
        guard let root = self.first else {
            fatalError("body is empty")
        }
        let output = visit(root)
        return inputs.flatMap { ["-i", $0.fileName] } + ["-filter_complex", streams.joined(separator: ";"), "-map", "[\(output)]"]
    }
}


struct SomeVideo: Video {
    let showLogo: Bool
    var body: [VideoBuildingBlock] {
        ZStack {
            Resource("wwdc2020.mp4")
            Resource("wwdc1990.mkv", offset: CGPoint(x: 1200, y: 100))
            if showLogo {
                Resource("cocoaheads.png", offset: CGPoint(x: 100, y: 800))
            }
        }
    }
}
 
struct MainMovie: Video {
    var body: [VideoBuildingBlock] {
        HStack {
            SomeVideo(showLogo: false)
            SomeVideo(showLogo: true)
        }
    }
}

let args = MainMovie().body.ffmpegArgs()

func makeCommand(args: [String]) -> String {
    let quoted = ["ffmpeg"] + args.map { $0.hasPrefix("-") ? $0 : "\"\($0)\"" } + ["output.mp4"]
    return quoted.joined(separator: " ")
}

print(makeCommand(args: args))
