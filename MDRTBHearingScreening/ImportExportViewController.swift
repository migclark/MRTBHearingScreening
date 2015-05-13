//
//  ImportExportViewController.swift
//  MDRTBHearingScreening
//
//  Created by Miguel Clark on 5/10/15.
//  Copyright (c) 2015 Miguel Clark. All rights reserved.
//

import UIKit
import CoreData


class ImportExportViewController: UIViewController, UIDocumentInteractionControllerDelegate {

    @IBOutlet weak var progresslabel: UILabel!
    @IBOutlet weak var progressindicator: UIProgressView!
    @IBOutlet weak var activityindicator: UIActivityIndicatorView!
    @IBOutlet weak var sharebutton: UIButton!
    @IBOutlet weak var cancelbutton: UIButton!
    
    @IBAction func sharebutton_tapped(sender: UIButton) {
        presentSharingView(sender)
    }
    @IBAction func cancelbutton_tapped(sender: UIButton) {
        controllerdDismissed = true
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    enum Mode {
        case ImportFromCSV
        case ExportAllToCSV
        case ExportStudyOnlyToCSV
    }
    var currentMode: Mode!
    
    var importFileURL: NSURL?
    var exportFileURL: NSURL?
    var controllerdDismissed = false
    
    var documentInteractionController: UIDocumentInteractionController!
    
    func presentSharingView(sender:UIButton) {
        if let url = exportFileURL {
            documentInteractionController = UIDocumentInteractionController(URL: url)
            documentInteractionController.presentOptionsMenuFromRect(CGRect(x: sender.frame.width/2, y: 0, width: 1, height: 1), inView: sender, animated: true)
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        activityindicator.startAnimating()
        progressindicator.setProgress(0.0, animated: false)
        sharebutton.hidden = true
        
        if currentMode == Mode.ImportFromCSV {
            title = "Importing Tests From File"
            progresslabel.text = "Importing..."
        } else if currentMode == Mode.ExportAllToCSV {
            title = "Exporting All Tests to CSV"
            progresslabel.text = "Exporting..."
        } else if currentMode == Mode.ExportStudyOnlyToCSV {
            title = "Exporting Only Study Tests to CSV"
            progresslabel.text = "Exporting..."
        }
        
        let importBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, { () -> Void in
            if let url = self.importFileURL {
               self.importTests(url)
                dispatch_async(dispatch_get_main_queue(), {
                    self.activityindicator.stopAnimating()
                    self.progressindicator.setProgress(1.0, animated: false)
                    self.progresslabel.text = "Import Complete"
                    self.sharebutton.hidden = true
                    self.cancelbutton.titleLabel?.text = "Close"
                    return
                })
                return
            }
        })
        let exportBlock = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, { () -> Void in
            self.exportFileURL = self.exportTests(studyOnly: self.currentMode == Mode.ExportStudyOnlyToCSV)
            dispatch_async(dispatch_get_main_queue(), {
                self.activityindicator.stopAnimating()
                self.progressindicator.setProgress(1.0, animated: false)
                self.progresslabel.text = "Export Complete"
                self.sharebutton.hidden = false
                self.cancelbutton.setTitle("Close", forState: UIControlState.Normal)
                self.presentSharingView(self.sharebutton)
                return
            })
            return
        })
        
        if currentMode == Mode.ImportFromCSV {
            if let url = self.importFileURL {
                self.importTests(url)
            }
        } else if currentMode == Mode.ExportAllToCSV || currentMode == Mode.ExportStudyOnlyToCSV {
            dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), exportBlock)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    
    func importTests(url:NSURL) {
        
        // parse file into array dictionary and create Test managed object
        let importStart = NSDate()
        let importedString = NSString(contentsOfURL: url, encoding: NSUTF8StringEncoding, error: nil)
        var importedArray = [String]()
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        
        // create a seperate MOC to handle imported objects
        let tempContext = NSManagedObjectContext(concurrencyType: NSManagedObjectContextConcurrencyType.PrivateQueueConcurrencyType)
        tempContext.parentContext = appDelegate.managedObjectContext
        
        tempContext.performBlock { () -> Void in
            
            importedString?.enumerateLinesUsingBlock({ (line,a) -> Void in
                importedArray.append(line)
            })
            
            let keyString = importedArray.first
            if let keyString = importedArray.first {
                let keys = keyString.componentsSeparatedByString(",")
                for var i = 1; i < importedArray.count; i++ {
                    let valueString = importedArray[i]
                    let values = valueString.componentsSeparatedByString(",")
                    let test = NSEntityDescription.insertNewObjectForEntityForName("Test", inManagedObjectContext: tempContext) as! Test
                    for var j = 0; j < keys.count; j++ {
                        // assume all imported values are String
                        test.setValue(values[j], forKey: keys[j])
                    }
                    
                    dispatch_async(dispatch_get_main_queue(), {
                        self.progresslabel.text = "\(i) of \(importedArray.count-1) imported"
                        self.progressindicator.setProgress(Float(100*i/importedArray.count-1)/100, animated: true)
                        return
                    })
                    
                    if self.controllerdDismissed {
                        println("controllerdDismissed block cancelled")
                        return
                    }
                }
                
                dispatch_async(dispatch_get_main_queue(), {
                    self.progresslabel.text = "Saving context..."
                    self.progressindicator.setProgress(0.9, animated: true)
                    self.cancelbutton.titleLabel?.text = "Close"
                    return
                })
                
                // save temp context up to parent
                var error: NSError?
                println("saving tempContext")
                if !tempContext.save(&error) {
                    println("error saving context")
                }
                
                // save main context to persistant store
                if let mainContext = appDelegate.managedObjectContext {
                    mainContext.performBlock({ () -> Void in
                        var error: NSError?
                        println("saving mainContext")
                        if !mainContext.save(&error) {
                            println("error saving context")
                        }
                        dispatch_async(dispatch_get_main_queue(), {
                            self.progresslabel.text = "Import Complete"
                            self.progressindicator.setProgress(1.0, animated: true)
                            self.activityindicator.stopAnimating()
                            self.cancelbutton.setTitle("Close", forState: UIControlState.Normal)
                            return
                        })
                        
                    })
                }
            }
        }
        
        
        
        // delete file from inbox
        println("deleting \(url)")
        NSFileManager.defaultManager().removeItemAtURL(url, error: nil)
        
        return
    }
    
    func exportTests(studyOnly:Bool = false) -> NSURL? {
        let start = NSDate()
        let appDelegate = UIApplication.sharedApplication().delegate as! AppDelegate
        let moc = appDelegate.managedObjectContext!
        let exportDateString = Test.getStringFromDate(start, includeTime: false)
        let exportFileName = (studyOnly) ? "export-study-\(exportDateString).csv" : "export-all-\(exportDateString).csv"
        let exportFileUrl = appDelegate.applicationDocumentsDirectory.URLByAppendingPathComponent(exportFileName)

        // create fetchrequest
        let fr = NSFetchRequest(entityName: "Test")
        let sortDescriptor = NSSortDescriptor(key: "test_date", ascending: false)
        fr.sortDescriptors = [sortDescriptor]
        if studyOnly {
            let predicate = NSPredicate(format: "patient_consent == \"1\"", argumentArray: nil)
            fr.predicate = predicate
        }
        
        if let tests = moc.executeFetchRequest(fr, error: nil) as? [Test] {
            var csvString = NSMutableString()
            
            if let entity = NSEntityDescription.entityForName("Test", inManagedObjectContext: moc) {
                if let headers = Test.csvHeaders(entity) {
                    csvString.appendString(",".join(headers)+"\n")
                    var count = 0
                    for test in tests {
                        var values = [String]()
                        for key in headers {
                            let value = test.valueForKey(key) as? String ?? ""
                            values.append("\"\(value)\"")
                        }
                        csvString.appendString(",".join(values)+"\n")
                        
                        count++
                        dispatch_async(dispatch_get_main_queue(), {
                            self.progressindicator.setProgress(Float(count*100/tests.count)/100, animated: true)
                            self.progresslabel.text = "\(count) of \(tests.count) exported"
                        })
                        if count%100 == 0 {
                            println("\(count) exported")
                        }
                        if controllerdDismissed {
                            println("controllerdDismissed block cancelled")
                            return nil
                        }
                    }
                }
            }
            
            var error: NSError?
            csvString.writeToURL(exportFileUrl, atomically: true, encoding: NSUTF8StringEncoding, error: &error)
            let timeInterval = -start.timeIntervalSinceNow
            println("export completed. Time inteval :: \(timeInterval)")
            return exportFileUrl
        }
        return nil
    }

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
