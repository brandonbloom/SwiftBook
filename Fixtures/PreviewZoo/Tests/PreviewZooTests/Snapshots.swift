import SwiftBookTesting
import Testing

// Parameterized previews aren't supported yet (see `preview-arguments` in docs/plan.md).
#SwiftBookTests(excluding: ["PreviewZoo/Arguments/Badge arguments"])
