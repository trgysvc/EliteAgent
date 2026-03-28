import Foundation

public final class CoordinateBridge: Sendable {
    public static let shared = CoordinateBridge()
    
    private init() {}
    
    public func centerOf(rect: CGRect) -> (x: Double, y: Double) {
        let x = rect.origin.x + (rect.size.width / 2.0)
        let y = rect.origin.y + (rect.size.height / 2.0)
        return (x, y)
    }
    
    public func generateClickScript(x: Double, y: Double) -> String {
        return """
        (function() {
            var el = document.elementFromPoint(\(x), \(y));
            if (el) {
                var event = new MouseEvent('click', {
                    'view': window,
                    'bubbles': true,
                    'cancelable': true,
                    'clientX': \(x),
                    'clientY': \(y)
                });
                el.dispatchEvent(event);
                return 'Clicked ' + el.tagName + ' at (\(x), \(y))';
            }
            return 'No element at (\(x), \(y))';
        })()
        """
    }
}
