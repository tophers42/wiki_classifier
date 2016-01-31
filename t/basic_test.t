use strict;
use warnings;

use Test::More tests => 6;
use Test::Moose;
use Log::Log4perl;


BEGIN {
    Log::Log4perl->easy_init( { file => 'STDOUT' } );
    use_ok( 'Wiki::Classifier' );
}

# Build and save a model based on two directories of training data.
# parallelized with 10 processes.
my $model_builder = new_ok( 'Wiki::Classifier' => [
    training_directories => [ 't/training_data/positive', 't/training_data/negative' ],
    save_model => 't/models/test.model',
    ]
);

ok( $model_builder->run, 'Model is built ok' );


# Using a pre-built model, predict the classification of a new wiki page.
my $model_loader = new_ok( 'Wiki::Classifier' => [
    model => 't/models/test.model',
    predict_files => [ 't/predict_me.html' ],
    ]
);

ok( $model_loader->run, 'Model predicts ok' );

# confirm the prediction is as expected.

my $expected_predictions = [
    {
        'diseaseDB_links' => [],
        'path' => 't/predict_me.html',
        'score_negative' => '1',
        'score_positive' => '0',
        'title' => 'Sertraline'
    }
];

is_deeply( $model_loader->predictions, $expected_predictions );

unlink( 't/models/test.model' );



