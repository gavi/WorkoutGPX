import SwiftUI

// Share sheet for sharing GPX files
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Prevent dismissal of activity view controller
        controller.completionWithItemsHandler = { (activityType, completed, returnedItems, error) in
            // This ensures the sharing sheet stays visible until user completes their action
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}