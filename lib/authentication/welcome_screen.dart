import 'package:flutter/material.dart';
import 'package:carousel_slider/carousel_slider.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  WelcomeScreenState createState() => WelcomeScreenState();
}

class WelcomeScreenState extends State<WelcomeScreen> {
  int _currentIndex = 0;

  final List<Slide> slides = [
    Slide(
      image: 'assets/nyumbasmart.jpg',
      title: 'Facility Management Software',
      subtitle: 'Developed by JV ALMA C.I.S',
    ),
    Slide(
      image: 'assets/fm.jpg',
      title: 'Digitize Your Facility Management',
      subtitle: 'NyumbaSmart keeps your buildings and facilities secure and efficient. Log in to manage maintenance, billing, and more with confidence.',
    ),
    Slide(
      images: ['assets/aircon.jpg', 'assets/hvac.jpg'],
      title: 'Optimize Your System and Electricals',
      subtitle: 'Ensure your systems and electricals are running smoothly with our comprehensive management tools.',
    ),
    Slide(
      image: 'assets/teams.jpg',
      title: 'Track Maintenance with Ease',
      subtitle: 'Monitor work orders and preventive maintenance in real-time for seamless operations.',
    ),
    Slide(
      image: 'assets/maintenance.jpg',
      title: 'Monitor Maintenance Team Activities',
      subtitle: 'Track work done by the team as they record activities and updates using the app.',
    ),
    Slide(
      image: 'assets/accountant1.jpg',
      title: 'Simplify Reports and Billing Processes',
      subtitle: 'Manage facility costs and get customized reports with system integrated tools.',
    ),
    Slide(
      image: 'assets/lock2.jpg',
      title: 'Secure Access for Authorized Users',
      subtitle: 'Protect sensitive data with role-based access for facility staff only.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;
    final isTablet = screenWidth >= 600 && screenWidth < 1200;

    return Scaffold(
      body: Stack(
        children: [
          CarouselSlider(
            options: CarouselOptions(
              height: MediaQuery.of(context).size.height,
              enlargeCenterPage: true,
              enableInfiniteScroll: true,
              autoPlay: false,
              viewportFraction: 1.0,
              onPageChanged: (index, reason) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
            items: slides.map((slide) {
              return Builder(
                builder: (BuildContext context) {
                  return SizedBox(
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.height,
                    child: slide.image == 'assets/nyumbasmart.jpg'
                        ? Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Center(
                                  child: Image.asset(
                                    slide.image!,
                                    height: isMobile ? 100.0 : isTablet ? 150.0 : 200.0,
                                    fit: BoxFit.contain,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      slide.title,
                                      style: TextStyle(
                                        fontSize: isMobile ? 20.0 : isTablet ? 22.0 : 24.0,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.black87,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      slide.subtitle,
                                      style: TextStyle(
                                        fontSize: isMobile ? 14.0 : isTablet ? 15.0 : 16.0,
                                        color: Colors.black87,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : (slide.images != null && slide.images!.length > 1
                            ? Stack(
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Image.asset(
                                          slide.images![0],
                                          fit: BoxFit.cover,
                                          height: MediaQuery.of(context).size.height,
                                        ),
                                      ),
                                      Expanded(
                                        child: Image.asset(
                                          slide.images![1],
                                          fit: BoxFit.cover,
                                          height: MediaQuery.of(context).size.height,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Positioned(
                                    left: 0,
                                    right: 0,
                                    bottom: 150.0,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            slide.title,
                                            style: TextStyle(
                                              fontSize: isMobile ? 20.0 : isTablet ? 22.0 : 24.0,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            slide.subtitle,
                                            style: TextStyle(
                                              fontSize: isMobile ? 14.0 : isTablet ? 15.0 : 16.0,
                                              color: Colors.white,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : Container(
                                decoration: BoxDecoration(
                                  image: DecorationImage(
                                    image: AssetImage(slide.image!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(16.0, 0, 16.0, 150.0),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      Text(
                                        slide.title,
                                        style: TextStyle(
                                          fontSize: isMobile ? 20.0 : isTablet ? 22.0 : 24.0,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        slide.subtitle,
                                        style: TextStyle(
                                          fontSize: isMobile ? 14.0 : isTablet ? 15.0 : 16.0,
                                          color: Colors.white,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                              )),
                  );
                },
              );
            }).toList(),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 50.0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/login');
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: isMobile ? 6.0 : isTablet ? 8.0 : 10.0,
                          horizontal: isMobile ? 12.0 : isTablet ? 15.0 : 18.0,
                        ),
                      ),
                      child: Text(
                        'Sign In',
                        style: TextStyle(
                          fontSize: isMobile ? 14.0 : isTablet ? 16.0 : 18.0,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: () {
                        Navigator.pushNamed(context, '/needAccount');
                      },
                      child: Text(
                        'Having Trouble Signing In? Need an Account',
                        style: TextStyle(
                          color: Colors.blue,
                          fontSize: isMobile ? 14.0 : isTablet ? 16.0 : 18.0,
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(slides.length, (index) {
                        return Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4.0),
                          width: 10.0,
                          height: 10.0,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentIndex == index ? Colors.blueGrey : Colors.grey,
                          ),
                        );
                      }),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Slide {
  final String? image;
  final List<String>? images;
  final String title;
  final String subtitle;

  Slide({this.image, this.images, required this.title, required this.subtitle});
}