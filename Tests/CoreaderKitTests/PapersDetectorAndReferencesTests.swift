import Foundation
import Testing
@testable import CoreaderKit

// MARK: PaperDetector

private let arxivFirstPage = """
arXiv:1706.03762v7 [cs.CL] 2 Aug 2023
Attention Is All You Need
Ashish Vaswani∗ Noam Shazeer∗ Niki Parmar∗
Google Brain Google Brain Google Research
avaswani@google.com noam@google.com nikip@google.com
Abstract
The dominant sequence transduction models are based on complex recurrent or
convolutional neural networks that include an encoder and a decoder.
1 Introduction
Recurrent neural networks, long short-term memory and gated recurrent neural networks
in particular, have been firmly established as state of the art approaches.
"""

@Test func paperDetectorReadsAnArxivStamp() {
    let hints = PaperDetector.detect(firstPagesText: arxivFirstPage, fileName: "download.pdf", pdfTitle: nil, pageCount: 15)
    #expect(hints.isLikelyPaper)
    #expect(hints.arxivID == "1706.03762")
    #expect(hints.doi == nil)
    #expect(hints.guessedTitle == "Attention Is All You Need")
}

@Test func paperDetectorUsesTheFileNameAndInfoTitle() {
    let hints = PaperDetector.detect(firstPagesText: "", fileName: "2301.01234v2.pdf", pdfTitle: "A Fine  Paper Title", pageCount: 9)
    #expect(hints.isLikelyPaper)
    #expect(hints.arxivID == "2301.01234")
    #expect(hints.guessedTitle == "A Fine Paper Title")
    // Titles left behind by the typesetting tool are ignored.
    for junk in ["Microsoft Word - draft_final.docx", "paper.pdf", "untitled", "main", "arXiv:1706.03762v7 [cs.CL]"] {
        let guess = PaperDetector.detect(firstPagesText: arxivFirstPage, fileName: "x.pdf", pdfTitle: junk, pageCount: 9).guessedTitle
        #expect(guess == "Attention Is All You Need", "info title: \(junk)")
    }
}

@Test func paperDetectorRecognisesAJournalArticleByStructure() {
    let text = """
    Journal of Machine Learning Research 15 (2014) 1929-1958
    Dropout: A Simple Way to Prevent Neural Networks from
    Overfitting
    Nitish Srivastava nitish@cs.toronto.edu
    Department of Computer Science, University of Toronto
    Abstract
    Deep neural nets with a large number of parameters are very powerful machine learning systems.
    Keywords: neural networks, regularization, model combination, deep learning
    1. Introduction
    Deep neural networks contain multiple non-linear hidden layers.
    https://doi.org/10.5555/2627435.2670313
    """
    let hints = PaperDetector.detect(firstPagesText: text, fileName: "srivastava14a.pdf", pdfTitle: "srivastava14a.dvi", pageCount: 30)
    #expect(hints.isLikelyPaper)
    #expect(hints.doi == "10.5555/2627435.2670313")
    #expect(hints.arxivID == nil)
    #expect(hints.guessedTitle == "Dropout: A Simple Way to Prevent Neural Networks from Overfitting")
}

@Test func paperDetectorTreatsAnArxivDOIAsAnArxivID() {
    let hints = PaperDetector.detect(firstPagesText: "https://doi.org/10.48550/arXiv.2301.01234\nAbstract\n",
                                     fileName: "a.pdf", pdfTitle: nil, pageCount: 8)
    #expect(hints.arxivID == "2301.01234")
    #expect(hints.doi == nil)
}

@Test func paperDetectorLeavesBooksAlone() {
    let book = """
    THINKING, FAST AND SLOW
    Daniel Kahneman
    Farrar, Straus and Giroux, New York
    ISBN 978-0-374-27563-1
    All rights reserved. No part of this book may be reproduced.
    Table of Contents
    Introduction
    Chapter 1 The Characters of the Story
    """
    let hints = PaperDetector.detect(firstPagesText: book, fileName: "Thinking Fast and Slow.pdf",
                                     pdfTitle: "Thinking, Fast and Slow", pageCount: 512)
    #expect(!hints.isLikelyPaper)
    #expect(hints.arxivID == nil)
    #expect(hints.guessedTitle == "Thinking, Fast and Slow")

    let nothing = PaperDetector.detect(firstPagesText: "", fileName: "scan0001.pdf", pdfTitle: nil, pageCount: 3)
    #expect(!nothing.isLikelyPaper)
    #expect(nothing.guessedTitle == nil)
}

// MARK: ReferenceParser

@Test func referencesSectionIsFoundAndStopsAtTheAppendix() throws {
    let paper = """
    Contents
    References
    1 Introduction
    We build on prior work [1, 2].
    6 Conclusion
    Done.
    References
    [1] A. Author. First paper. 2001.
    [2] B. Author. Second paper. 2002.
    Appendix A Proofs
    Lemma 1.
    """
    let section = try #require(ReferenceParser.referencesSection(in: paper))
    #expect(section.hasPrefix("[1] A. Author"))
    #expect(section.hasSuffix("Second paper. 2002."))
    #expect(ReferenceParser.referencesSection(in: "No bibliography here.\nJust text.") == nil)
    #expect(ReferenceParser.referencesSection(in: "7. REFERENCES\n[1] X. Y. Zed. A thing. 1999.")?.hasPrefix("[1]") == true)
}

@Test func referencesBracketNumberedStyle() {
    let text = """
    [1] Jimmy Lei Ba, Jamie Ryan Kiros, and Geoffrey E Hinton. Layer normalization. arXiv preprint
    arXiv:1607.06450, 2016.
    [2] Dzmitry Bahdanau, Kyunghyun Cho, and Yoshua Bengio. Neural machine translation by jointly
    learning to align and translate. CoRR, abs/1409.0473, 2014.
    13
    [3] K. He, X. Zhang, S. Ren, and J. Sun, “Deep residual learning for image recognition,” in Proc. IEEE
    Conf. Comput. Vis. Pattern Recognit., 2016, pp. 770–778. doi: 10.1109/CVPR.2016.90.
    [4] Nitish Srivastava, Geoffrey E Hinton, Alex Krizhevsky, Ilya Sutskever, and Ruslan Salakhutdinov.
    Dropout: a simple way to prevent neural networks from overfitting. Journal of Machine Learning
    Research, 15(1):1929–1958, 2014.
    """
    let refs = ReferenceParser.parse(referencesText: text)
    #expect(refs.map(\.id) == ["1", "2", "3", "4"])

    #expect(refs[0].title == "Layer normalization")
    #expect(refs[0].authors == ["Jimmy Lei Ba", "Jamie Ryan Kiros", "Geoffrey E Hinton"])
    #expect(refs[0].arxivID == "1607.06450")
    #expect(refs[0].year == 2016)

    #expect(refs[1].title == "Neural machine translation by jointly learning to align and translate")
    #expect(refs[1].arxivID == "1409.0473")
    #expect(refs[1].year == 2014)
    #expect(!refs[1].raw.contains("13"))   // the stray page number is gone

    #expect(refs[2].title == "Deep residual learning for image recognition")
    #expect(refs[2].authors == ["K. He", "X. Zhang", "S. Ren", "J. Sun"])
    #expect(refs[2].doi == "10.1109/cvpr.2016.90")
    #expect(refs[2].year == 2016)

    #expect(refs[3].title == "Dropout: a simple way to prevent neural networks from overfitting")
    #expect(refs[3].authors.count == 5)
    #expect(refs[3].year == 2014)   // not 1929 or 1958 from the page range
}

@Test func referencesPlainNumberedStyleNeedsCountingNumbers() {
    let text = """
    1. LeCun, Y., Bengio, Y. & Hinton, G. Deep learning. Nature 521, 436–444 (2015).
    2. Krizhevsky, A., Sutskever, I. & Hinton, G. ImageNet classification with deep convolutional
    neural networks. In Proc. Advances in Neural Information Processing Systems 25 1090–1098
    2012. This report was a breakthrough.
    3. Hinton, G. E. et al. Deep neural networks for acoustic modeling in speech recognition. IEEE
    Signal Process. Mag. 29, 82–97 (2012).
    """
    let refs = ReferenceParser.parse(referencesText: text)
    #expect(refs.map(\.id) == ["1", "2", "3"])   // "2012. This report" did not start an entry
    #expect(refs[0].authors == ["Y. LeCun", "Y. Bengio", "G. Hinton"])
    #expect(refs[0].title == "Deep learning")
    #expect(refs[0].year == 2015)
    #expect(refs[1].title == "ImageNet classification with deep convolutional neural networks")
    #expect(refs[2].authors == ["G. E. Hinton"])
    #expect(refs[2].title == "Deep neural networks for acoustic modeling in speech recognition")
}

@Test func referencesAuthorYearStyles() {
    let text = """
    Kingma, D. P. and Ba, J. Adam: A method for stochastic optimization. In International Conference
    on Learning Representations, 2015.
    Vaswani, A., Shazeer, N., & Polosukhin, I. (2017). Attention is all you need. Advances in Neural
    Information Processing Systems, 30. https://doi.org/10.5555/3295222.3295349
    Ashish Vaswani and Noam Shazeer. 2017. Attention is not all you need. In Proceedings of
    Something, pages 1–10.
    Laurens van der Maaten and Geoffrey Hinton. 2008. Visualizing data using t-SNE. Journal of Machine
    Learning Research, 9:2579–2605.
    """
    let refs = ReferenceParser.parse(referencesText: text)
    #expect(refs.count == 4)
    #expect(refs.map(\.id) == ["Kingma2015", "Vaswani2017", "Vaswani2017b", "Maaten2008"])

    #expect(refs[0].authors == ["D. P. Kingma", "J. Ba"])
    #expect(refs[0].title == "Adam: A method for stochastic optimization")

    #expect(refs[1].authors == ["A. Vaswani", "N. Shazeer", "I. Polosukhin"])
    #expect(refs[1].title == "Attention is all you need")
    #expect(refs[1].doi == "10.5555/3295222.3295349")
    #expect(refs[1].year == 2017)

    #expect(refs[2].authors == ["Ashish Vaswani", "Noam Shazeer"])
    #expect(refs[2].title == "Attention is not all you need")

    #expect(refs[3].authors == ["Laurens van der Maaten", "Geoffrey Hinton"])
    #expect(refs[3].title == "Visualizing data using t-SNE")
    #expect(refs[3].year == 2008)
}

@Test func referencesSeparatedByBlankLinesAndHyphenatedWords() {
    let text = """
    Hochreiter, S. and Schmidhuber, J. Long short-term mem-
    ory. Neural Computation, 9(8):1735–1780, 1997a.

    Unreadable entry without anything useful

    Bengio, Y. Learning deep architectures for AI. Foundations and Trends in Machine Learning, 2009.
    """
    let refs = ReferenceParser.parse(referencesText: text)
    #expect(refs.count == 3)
    #expect(refs[0].id == "Hochreiter1997a")
    #expect(refs[0].title == "Long short-term memory")
    #expect(refs[0].raw.contains("Long short-term memory"))
    #expect(refs[1].id == "ref2")
    #expect(refs[1].title == nil)
    #expect(refs[1].raw == "Unreadable entry without anything useful")
    #expect(refs[2].id == "Bengio2009")
    #expect(ReferenceParser.parse(referencesText: "").isEmpty)
}

@Test func referencesAlphaLabels() {
    let refs = ReferenceParser.parse(referencesText: """
    [VSP+17] A. Vaswani, N. Shazeer, and N. Parmar. Attention is all you need. NeurIPS, 2017.
    [Knu84] D. E. Knuth. Literate programming. The Computer Journal, 27(2):97–111, 1984.
    """)
    #expect(refs.map(\.id) == ["VSP+17", "Knu84"])
    #expect(refs[1].authors == ["D. E. Knuth"])
    #expect(refs[1].title == "Literate programming")
    #expect(refs[1].year == 1984)
}

@Test func citationLabelsNumeric() {
    #expect(ReferenceParser.citationLabels(in: "as shown in [3, 7-9] and later [12]; see also [3].") == ["3", "7", "8", "9", "12"])
    #expect(ReferenceParser.citationLabels(in: "ranges [1–3], [ 5 ; 6 ]") == ["1", "2", "3", "5", "6"])
    // Not citations: intervals, indices, years in brackets with words.
    #expect(ReferenceParser.citationLabels(in: "x in [0, 1) and a[i] = b[1024] with [sic]") == [])
    #expect(ReferenceParser.citationLabels(in: "backwards [9-3]") == ["9"])
}

@Test func citationLabelsAuthorYear() {
    #expect(ReferenceParser.citationLabels(in: "attention (Vaswani et al., 2017) changed everything") == ["Vaswani2017"])
    #expect(ReferenceParser.citationLabels(in: "(see Bahdanau and Cho, 2015; Vaswani et al., 2017a, 2018; e.g. Kingma & Ba 2015)")
        == ["Bahdanau2015", "Vaswani2017a", "Vaswani2018", "Kingma2015"])
    #expect(ReferenceParser.citationLabels(in: "Vaswani et al. (2017) and van der Maaten and Hinton (2008) showed") == ["Vaswani2017", "Maaten2008"])
    #expect(ReferenceParser.citationLabels(in: "In 2017 (a good year) nothing was cited.") == [])
    #expect(ReferenceParser.citationLabels(in: "mixed [2] and (Smith, 2020)") == ["2", "Smith2020"])
}

@Test func citationLabelsMatchReferenceIDs() {
    let refs = ReferenceParser.parse(referencesText: """
    Kingma, D. P. and Ba, J. Adam: A method for stochastic optimization. In ICLR, 2015.

    Laurens van der Maaten and Geoffrey Hinton. 2008. Visualizing data using t-SNE. JMLR, 9:2579–2605.
    """)
    let cited = ReferenceParser.citationLabels(in: "We use Adam (Kingma and Ba, 2015) and t-SNE (van der Maaten and Hinton, 2008).")
    #expect(cited == refs.map(\.id))
}
