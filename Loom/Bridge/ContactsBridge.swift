import Foundation
import JavaScriptCore
import Contacts

// Implements Loom.contacts — search, create, update, delete via CNContactStore.
final class ContactsBridge {
    private let ctx: JSContext
    private let store = CNContactStore()

    nonisolated init(ctx: JSContext) {
        self.ctx = ctx
    }

    nonisolated func makeObject() -> JSValue {
        let obj = JSValue(newObjectIn: ctx)!
        let capturedCtx = ctx

        let searchBlock: @convention(block) (JSValue) -> JSValue = { [weak self] queryVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let query = queryVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                self.store.requestAccess(for: .contacts) { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Contacts permission denied"); return }
                    let keys: [CNKeyDescriptor] = [
                        CNContactGivenNameKey as CNKeyDescriptor,
                        CNContactFamilyNameKey as CNKeyDescriptor,
                        CNContactEmailAddressesKey as CNKeyDescriptor,
                        CNContactPhoneNumbersKey as CNKeyDescriptor,
                        CNContactIdentifierKey as CNKeyDescriptor,
                    ]
                    let req = CNContactFetchRequest(keysToFetch: keys)
                    req.predicate = CNContact.predicateForContacts(matchingName: query)
                    var results: [[String: Any]] = []
                    do {
                        try self.store.enumerateContacts(with: req) { contact, _ in
                            results.append(contactDict(contact))
                        }
                        resolve(results as NSArray)
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        let createBlock: @convention(block) (JSValue) -> JSValue = { [weak self] fieldsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let fields = fieldsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                self.store.requestAccess(for: .contacts) { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Contacts permission denied"); return }
                    let contact = mutableContact(from: fields)
                    let req = CNSaveRequest()
                    req.add(contact, toContainerWithIdentifier: nil)
                    do {
                        try self.store.execute(req)
                        resolve(["id": contact.identifier] as NSDictionary)
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        let updateBlock: @convention(block) (JSValue, JSValue) -> JSValue = { [weak self] idVal, fieldsVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let id = idVal.toString() ?? ""
            let fields = fieldsVal.toDictionary() as? [String: Any] ?? [:]
            return self.makePromise { resolve, reject in
                self.store.requestAccess(for: .contacts) { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Contacts permission denied"); return }
                    let keys: [CNKeyDescriptor] = [
                        CNContactGivenNameKey as CNKeyDescriptor,
                        CNContactFamilyNameKey as CNKeyDescriptor,
                        CNContactEmailAddressesKey as CNKeyDescriptor,
                        CNContactPhoneNumbersKey as CNKeyDescriptor,
                    ]
                    do {
                        let contact = try self.store.unifiedContact(withIdentifier: id, keysToFetch: keys)
                        let mutable = contact.mutableCopy() as! CNMutableContact
                        applyFields(fields, to: mutable)
                        let req = CNSaveRequest()
                        req.update(mutable)
                        try self.store.execute(req)
                        resolve(nil)
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        let deleteBlock: @convention(block) (JSValue) -> JSValue = { [weak self] idVal in
            guard let self else { return JSValue(undefinedIn: capturedCtx) }
            let id = idVal.toString() ?? ""
            return self.makePromise { resolve, reject in
                self.store.requestAccess(for: .contacts) { granted, error in
                    if let error { reject(error.localizedDescription); return }
                    guard granted else { reject("Contacts permission denied"); return }
                    do {
                        let contact = try self.store.unifiedContact(withIdentifier: id, keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
                        let mutable = contact.mutableCopy() as! CNMutableContact
                        let req = CNSaveRequest()
                        req.delete(mutable)
                        try self.store.execute(req)
                        resolve(nil)
                    } catch {
                        reject(error.localizedDescription)
                    }
                }
            }
        }

        obj.setObject(searchBlock, forKeyedSubscript: "search" as NSString)
        obj.setObject(createBlock, forKeyedSubscript: "create" as NSString)
        obj.setObject(updateBlock, forKeyedSubscript: "update" as NSString)
        obj.setObject(deleteBlock, forKeyedSubscript: "delete" as NSString)
        return obj
    }

    nonisolated private func makePromise(
        _ executor: (_ resolve: @escaping (Any?) -> Void, _ reject: @escaping (String) -> Void) -> Void
    ) -> JSValue {
        var resolvedVal: Any? = nil
        var rejectMsg: String? = nil
        let sema = DispatchSemaphore(value: 0)
        executor(
            { val in resolvedVal = val; sema.signal() },
            { msg in rejectMsg = msg; sema.signal() }
        )
        sema.wait()
        if let msg = rejectMsg {
            return ctx.objectForKeyedSubscript("__loomReject")?
                .call(withArguments: [msg]) ?? JSValue(undefinedIn: ctx)
        } else if let v = resolvedVal {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: [v]) ?? JSValue(undefinedIn: ctx)
        } else {
            return ctx.objectForKeyedSubscript("__loomResolve")?
                .call(withArguments: []) ?? JSValue(undefinedIn: ctx)
        }
    }
}

private func contactDict(_ c: CNContact) -> [String: Any] {
    [
        "id":        c.identifier,
        "firstName": c.givenName,
        "lastName":  c.familyName,
        "emails":    c.emailAddresses.map { $0.value as String },
        "phones":    c.phoneNumbers.map { $0.value.stringValue },
    ]
}

private func mutableContact(from fields: [String: Any]) -> CNMutableContact {
    let c = CNMutableContact()
    applyFields(fields, to: c)
    return c
}

private func applyFields(_ fields: [String: Any], to c: CNMutableContact) {
    if let v = (fields["givenName"] ?? fields["firstName"]) as? String { c.givenName = v }
    if let v = (fields["familyName"] ?? fields["lastName"]) as? String { c.familyName = v }
    if let emails = fields["emails"] as? [String] {
        c.emailAddresses = emails.map { CNLabeledValue(label: CNLabelWork, value: $0 as NSString) }
    }
    if let phones = fields["phones"] as? [String] {
        c.phoneNumbers = phones.map { CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: $0)) }
    }
}
