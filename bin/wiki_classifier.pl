#!/usr/bin/perl
# PODNAME: wiki_classifier.pl
# ABSTRACT: Given a model or training data, predict the classification for a wiki page.

=head1 Synopsis

# Build and save a model based on two directories of training data.
# parallelized with 10 processes.
wiki_classifier.pl --training_directories training_data/positive --training_directories training_data/negative --num_procs 10 --save_model models/disease_classifier.model

# Using a pre-built model, predict the classification of a new wiki page.
wiki_classifier.pl --model models/disease_classifier.model --predict_files my_test_wiki_page.html

=cut

use Wiki::Classifier;
use Log::Log4perl qw( :easy );

BEGIN { Log::Log4perl->easy_init( { file => 'STDOUT' } ) };

Wiki::Classifier->new_with_options()->run;
