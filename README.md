# Registration Automation

A Ruby-based automation script for handling event registrations with CAPTCHA solving capabilities.

## Features

- Automated form filling with random user data
- CAPTCHA solving using 2captcha service
- Selenium WebDriver for browser automation
- CSV export of registration data
- Retry mechanism for failed registrations

## Prerequisites

- Ruby 3.2.0 or higher
- Chrome browser installed
- 2captcha API key

## Installation

1. Clone the repository:
```bash
git clone https://github.com/YOUR_USERNAME/registration_automation.git
cd registration_automation
```

2. Install dependencies:
```bash
bundle install
```

## Configuration

1. Set your 2captcha API key in `lib/tasks/registration.rake`:
```ruby
CAPTCHA_API_KEY = "your_2captcha_api_key"
```

2. Adjust registration parameters as needed:
```ruby
NUM_OF_REGISTRATIONS = 1  # Number of registrations to perform
CAPTCHA_TIMEOUT = 60      # Timeout for CAPTCHA solving in seconds
```

## Usage

Run the registration process:
```bash
bundle exec rake load_test:simulate_registrations
```

Export registration data to CSV:
```bash
bundle exec rake load_test:export_data
```

Run both tasks in sequence:
```bash
bundle exec rake load_test:simulate_registrations load_test:export_data
```

## Output

The script generates CSV files with registration data including:
- Timestamp
- First Name
- Last Name
- Email
- Phone
- ZIP
- State
- Registration GUID
- Final URL

## License

MIT License
