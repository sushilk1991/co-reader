import Foundation

/// Real responses, fetched once during development and trimmed to the fields the client
/// reads. Kept as literals because the test target declares no resources.
enum PapersFixtures {
    /// GET https://export.arxiv.org/api/query?id_list=1706.03762
    static let arxivAttention = #"""
<?xml version='1.0' encoding='UTF-8'?>
<feed xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/" xmlns:arxiv="http://arxiv.org/schemas/atom" xmlns="http://www.w3.org/2005/Atom">
  <id>https://arxiv.org/api/zUwBFJ+vAUSpXAR7QFveSY/bZos</id>
  <title>arXiv Query: search_query=&amp;id_list=1706.03762&amp;start=0&amp;max_results=10</title>
  <updated>2026-11-22T18:00:02Z</updated>
  <link href="https://arxiv.org/api/query?search_query=&amp;start=0&amp;max_results=10&amp;id_list=1706.03762" type="application/atom+xml"/>
  <opensearch:itemsPerPage>10</opensearch:itemsPerPage>
  <opensearch:totalResults>1</opensearch:totalResults>
  <opensearch:startIndex>0</opensearch:startIndex>
  <entry>
    <id>http://arxiv.org/abs/1706.03762v7</id>
    <title>Attention Is All You Need</title>
    <updated>2023-08-02T00:41:18Z</updated>
    <link href="https://arxiv.org/abs/1706.03762v7" rel="alternate" type="text/html"/>
    <link href="https://arxiv.org/pdf/1706.03762v7" rel="related" type="application/pdf" title="pdf"/>
    <summary>The dominant sequence transduction models are based on complex recurrent or convolutional neural networks in an encoder-decoder configuration. The best performing models also connect the encoder and decoder through an attention mechanism. We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely. Experiments on two machine translation tasks show these models to be superior in quality while being more parallelizable and requiring significantly less time to train. Our model achieves 28.4 BLEU on the WMT 2014 English-to-German translation task, improving over the existing best results, including ensembles by over 2 BLEU. On the WMT 2014 English-to-French translation task, our model establishes a new single-model state-of-the-art BLEU score of 41.8 after training for 3.5 days on eight GPUs, a small fraction of the training costs of the best models from the literature. We show that the Transformer generalizes well to other tasks by applying it successfully to English constituency parsing both with large and limited training data.</summary>
    <category term="cs.CL" scheme="http://arxiv.org/schemas/atom"/>
    <category term="cs.LG" scheme="http://arxiv.org/schemas/atom"/>
    <published>2017-06-12T17:57:34Z</published>
    <arxiv:comment>15 pages, 5 figures</arxiv:comment>
    <arxiv:primary_category term="cs.CL"/>
    <author>
      <name>Ashish Vaswani</name>
    </author>
    <author>
      <name>Noam Shazeer</name>
    </author>
    <author>
      <name>Niki Parmar</name>
    </author>
    <author>
      <name>Jakob Uszkoreit</name>
    </author>
    <author>
      <name>Llion Jones</name>
    </author>
    <author>
      <name>Aidan N. Gomez</name>
    </author>
    <author>
      <name>Lukasz Kaiser</name>
    </author>
    <author>
      <name>Illia Polosukhin</name>
    </author>
  </entry>
</feed>
"""#

    /// What arXiv sends for an id it does not have: a feed with no entry.
    static let arxivEmpty = #"""
<?xml version='1.0' encoding='UTF-8'?>
<feed xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/" xmlns:arxiv="http://arxiv.org/schemas/atom" xmlns="http://www.w3.org/2005/Atom">
  <id>https://arxiv.org/api/abc</id>
  <title>arXiv Query: search_query=&amp;id_list=9999.99999&amp;start=0&amp;max_results=1</title>
  <opensearch:totalResults>0</opensearch:totalResults>
</feed>
"""#

    /// GET https://api.crossref.org/works/10.1038/nature14539
    static let crossrefDeepLearning = #"""
{
 "status": "ok",
 "message-type": "work",
 "message": {
  "DOI": "10.1038/nature14539",
  "title": [
   "Deep learning"
  ],
  "issued": {
   "date-parts": [
    [
     2015,
     5,
     27
    ]
   ]
  },
  "container-title": [
   "Nature"
  ],
  "link": [
   {
    "URL": "http://www.nature.com/articles/nature14539.pdf",
    "content-type": "application/pdf",
    "content-version": "vor",
    "intended-application": "text-mining"
   },
   {
    "URL": "http://www.nature.com/articles/nature14539",
    "content-type": "text/html",
    "content-version": "vor",
    "intended-application": "text-mining"
   }
  ],
  "URL": "https://doi.org/10.1038/nature14539",
  "type": "journal-article",
  "publisher": "Springer Science and Business Media LLC",
  "page": "436-444",
  "volume": "521",
  "published-print": {
   "date-parts": [
    [
     2015,
     5,
     28
    ]
   ]
  },
  "author": [
   {
    "given": "Yann",
    "family": "LeCun",
    "sequence": "first"
   },
   {
    "given": "Yoshua",
    "family": "Bengio",
    "sequence": "additional"
   },
   {
    "given": "Geoffrey",
    "family": "Hinton",
    "sequence": "additional"
   }
  ]
 }
}
"""#

    /// GET https://api.crossref.org/works?query.bibliographic=Deep residual learning for image recognition&rows=3
    /// The right paper is third; the first two are near misses.
    static let crossrefSearchResNet = #"""
{
 "status": "ok",
 "message-type": "work-list",
 "message": {
  "total-results": 4734934,
  "items": [
   {
    "abstract": "<jats:p>1 Insects recognition is crucial for taxonomy. It helps researchers to\nprocess tremendous and various ecology data. Most studies focus on\nfine-tuning the deep learning network or altering the algorithm to\nenhance the identification accuracy, and some</jats:p>",
    "DOI": "10.22541/au.170666177.72403547/v1",
    "type": "posted-content",
    "title": [
     "Multiple butterflies recognition based on deep residual learning and image analyze"
    ],
    "author": [
     {
      "given": "Tianyu",
      "family": "Xi"
     },
     {
      "given": "Jiangning",
      "family": "Wang"
     },
     {
      "given": "Yan",
      "family": "Han"
     },
     {
      "given": "Congtian",
      "family": "Lin"
     }
    ],
    "issued": {
     "date-parts": [
      [
       2024,
       1,
       31
      ]
     ]
    },
    "URL": "https://doi.org/10.22541/au.170666177.72403547/v1"
   },
   {
    "abstract": "<jats:p>Deep Residual Networks have recently been shown to significantly improve the performance of neural networks trained on ImageNet, with results beating all previous methods on this dataset by large margins in the image classification task. However, the</jats:p>",
    "DOI": "10.3390/app12188972",
    "type": "journal-article",
    "title": [
     "Deep Residual Learning for Image Recognition: A Survey"
    ],
    "author": [
     {
      "given": "Muhammad",
      "family": "Shafiq"
     },
     {
      "given": "Zhaoquan",
      "family": "Gu"
     }
    ],
    "container-title": [
     "Applied Sciences"
    ],
    "issued": {
     "date-parts": [
      [
       2022,
       9,
       7
      ]
     ]
    },
    "URL": "https://doi.org/10.3390/app12188972"
   },
   {
    "DOI": "10.1109/cvpr.2016.90",
    "title": [
     "Deep Residual Learning for Image Recognition"
    ],
    "author": [
     {
      "given": "Kaiming",
      "family": "He"
     },
     {
      "given": "Xiangyu",
      "family": "Zhang"
     },
     {
      "given": "Shaoqing",
      "family": "Ren"
     },
     {
      "given": "Jian",
      "family": "Sun"
     }
    ],
    "issued": {
     "date-parts": [
      [
       2016,
       6
      ]
     ]
    },
    "container-title": [
     "2016 IEEE Conference on Computer Vision and Pattern Recognition (CVPR)"
    ],
    "URL": "https://doi.org/10.1109/cvpr.2016.90",
    "type": "proceedings-article"
   }
  ]
 }
}
"""#

    /// GET https://api.semanticscholar.org/graph/v1/paper/search/match?query=Attention is all you need
    static let semanticScholarAttention = #"""
{
 "data": [
  {
   "paperId": "204e3073870fae3d05bcbc2f6a8e263d9b72e776",
   "externalIds": {
    "MAG": "2963403868",
    "DBLP": "journals/corr/VaswaniSPUJGKP17",
    "ArXiv": "1706.03762",
    "DOI": "10.48550/arXiv.1706.03762",
    "CorpusId": 13756489
   },
   "url": "https://www.semanticscholar.org/paper/204e3073870fae3d05bcbc2f6a8e263d9b72e776",
   "title": "Attention is All you Need",
   "venue": "Neural Information Processing Systems",
   "year": 2017,
   "openAccessPdf": {
    "url": "https://arxiv.org/pdf/1706.03762",
    "status": "CLOSED",
    "license": null
   },
   "authors": [
    {
     "authorId": "40348417",
     "name": "Ashish Vaswani"
    },
    {
     "authorId": "1846258",
     "name": "Noam Shazeer"
    },
    {
     "authorId": "3877127",
     "name": "N. Parmar"
    },
    {
     "authorId": "39328010",
     "name": "J. Uszkoreit"
    },
    {
     "authorId": "145024664",
     "name": "L. Jones"
    },
    {
     "authorId": "19177000",
     "name": "Aidan N. Gomez"
    },
    {
     "authorId": "40527594",
     "name": "L. Kaiser"
    },
    {
     "authorId": "3443442",
     "name": "I. Polosukhin"
    }
   ],
   "abstract": "The dominant sequence transduction models are based on complex recurrent or convolutional neural networks in an encoder-decoder configuration. The best performing models also connect the encoder and decoder through an attention mechanism. We propose a new simple network architecture, the Transformer, based solely on attention mechanisms, dispensing with recurrence and convolutions entirely. Experiments on two machine translation tasks show these models to be superior in quality while being more parallelizable and requiring significantly less time to train. Our model achieves 28.4 BLEU on the WMT 2014 English-to-German translation task, improving over the existing best results, including ensembles by over 2 BLEU. On the WMT 2014 English-to-French translation task, our model establishes a new single-model state-of-the-art BLEU score of 41.8 after training for 3.5 days on eight GPUs, a small fraction of the training costs of the best models from the literature. We show that the Transformer generalizes well to other tasks by applying it successfully to English constituency parsing both with large and limited training data.",
   "matchScore": 132.90685
  }
 ]
}
"""#
}
