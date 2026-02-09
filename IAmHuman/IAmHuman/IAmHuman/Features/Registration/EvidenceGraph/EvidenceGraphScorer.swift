// Features/Registration/EvidenceGraph/EvidenceGraphScorer.swift

import Foundation

final class EvidenceGraphScorer {

    func computeVerdict(
        moduleA: EvidenceAtom,
        moduleB: EvidenceAtom,
        moduleC: EvidenceAtom
    ) -> EvidenceGraphSummary {

        let edgeABScore = scoreEdgeAB(moduleA, moduleB)
        let edgeABPassed = edgeABScore >= 70

        let edgeACScore = scoreEdgeAC(moduleA, moduleC)
        let edgeACPassed = edgeACScore >= 65

        let edgeBCScore = scoreEdgeBC(moduleB, moduleC)
        let edgeBCPassed = edgeBCScore >= 60

        let edges = [
            GraphEdge(from: "A", to: "B", score: edgeABScore, passed: edgeABPassed),
            GraphEdge(from: "A", to: "C", score: edgeACScore, passed: edgeACPassed),
            GraphEdge(from: "B", to: "C", score: edgeBCScore, passed: edgeBCPassed)
        ]

        let grade: String
        if edgeABPassed && edgeACPassed && edgeBCPassed {
            grade = "A"
        } else if edgeABPassed && edgeACPassed {
            grade = "B"
        } else if edgeABPassed || edgeACPassed {
            grade = "C"
        } else {
            grade = "D"
        }

        let moduleScores: [String: Float] = [
            "A": moduleA.score,
            "B": moduleB.score,
            "C": moduleC.score
        ]

        let moduleAverage = (moduleA.score + moduleB.score + moduleC.score) / 3.0
        let edgeAverage = (edgeABScore + edgeACScore + edgeBCScore) / 3.0
        let trustScore = (moduleAverage * 0.65) + (edgeAverage * 0.35)

        return EvidenceGraphSummary(
            edges: edges,
            trustGrade: grade,
            trustScore: trustScore,
            moduleScores: moduleScores
        )
    }

    private func scoreEdgeAB(_ a: EvidenceAtom, _ b: EvidenceAtom) -> Float {
        let base = a.score * 0.55 + b.score * 0.45
        let consistencyPenalty = max(0, abs(a.score - b.score) - 30) * 0.5
        return clamp(base - consistencyPenalty)
    }

    private func scoreEdgeAC(_ a: EvidenceAtom, _ c: EvidenceAtom) -> Float {
        let base = a.score * 0.6 + c.score * 0.4
        let continuityPenalty = max(0, abs(a.score - c.score) - 35) * 0.4
        return clamp(base - continuityPenalty)
    }

    private func scoreEdgeBC(_ b: EvidenceAtom, _ c: EvidenceAtom) -> Float {
        let base = b.score * 0.5 + c.score * 0.5
        let rhythmPenalty = max(0, abs(b.score - c.score) - 40) * 0.3
        return clamp(base - rhythmPenalty)
    }

    private func clamp(_ value: Float) -> Float {
        min(100, max(0, value))
    }
}
