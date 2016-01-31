# wiki_classifier


* Build and save a model based on two directories of training data. parallelized with 10 processes.

```wiki_classifier.pl --training_directories training_data/positive --training_directories training_data/negative --num_procs 10 --save_model models/disease_classifier.model```

* Using a pre-built model, predict the classification of a new wiki page.

```wiki_classifier.pl --model models/disease_classifier.model --predict_files my_test_wiki_page.html```
