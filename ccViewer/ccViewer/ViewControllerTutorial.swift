//
//  ViewControllerTutorial.swift
//  ccViewer
//
//  Created by rei6 on 2019/03/14.
//  Copyright © 2019 lithium03. All rights reserved.
//

import UIKit

class ViewControllerTutorial: UIPageViewController, UIPageViewControllerDataSource {
    var pages: [UIViewController] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        for i in 1...3 {
            let p = storyboard!.instantiateViewController(withIdentifier: "Tutorial\(i)")
            p.title = "\(i-1)"
            pages += [p]
        }
        self.setViewControllers([pages[0]], direction: .forward, animated: true, completion: nil)
        self.dataSource = self
    }

    override var shouldAutorotate: Bool {
        return false
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
    }
    */

    func pageViewController(_ pageViewController: UIPageViewController, viewControllerBefore viewController: UIViewController) -> UIViewController? {
        var i = Int(viewController.title ?? "") ?? 0
        i -= 1
        if i < 0 {
            return nil
        }
        else {
            return pages[i]
        }
    }
    
    func pageViewController(_ pageViewController: UIPageViewController, viewControllerAfter viewController: UIViewController) -> UIViewController? {
        var i = Int(viewController.title ?? "") ?? 0
        i += 1
        if i >= pages.count {
            return nil
        }
        else {
            return pages[i]
        }

    }
    
    func presentationCount(for pageViewController: UIPageViewController) -> Int {
        return pages.count
    }
    
    func presentationIndex(for pageViewController: UIPageViewController) -> Int {
        return 0
    }
}
